{-
Copyright 2016 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Quasar.FS
  ( children
  , transitiveChildren
  , getNewName
  , move
  , listing
  , delete
  , messageIfFileNotFound
  , dirNotAccessible
  , fileNotAccessible
  , module Quasar.Error
  ) where

import SlamData.Prelude

import Control.Monad.Eff.Exception (error)

import Data.Argonaut as J
import Data.Array as Arr
import Data.Foldable as F
import Data.Lens ((.~), (^.), (^?), _Left)
import Data.List as List
import Data.Path.Pathy ((</>))
import Data.Path.Pathy as P
import Data.String as S

import Quasar.Advanced.QuasarAF as QF
import Quasar.Data.JSONMode as QDJ
import Quasar.Error (QError(..))
import Quasar.FS as QFS
import Quasar.FS.Mount as QFSM
import Quasar.FS.Resource as QR
import Quasar.Types (AnyPath, DirPath, FilePath)

import SlamData.Config as Config
import SlamData.FileSystem.Resource as R
import SlamData.Quasar.Class (class QuasarDSL, liftQuasar)
import SlamData.Quasar.Data as QD

import SlamData.Workspace.Model as WM
import SlamData.Workspace.Deck.Model as DM
import SlamData.Workspace.Card.Model as CM
import SlamData.Workspace.Card.CardType as CT
import SlamData.Workspace.Deck.DeckId as DID
import SlamData.Workspace.Card.Draftboard.Pane as Pane

children
  ∷ ∀ m
  . (Monad m, QuasarDSL m)
  ⇒ DirPath
  → m (Either QError (Array R.Resource))
children dir = runExceptT do
  cs ← ExceptT $ listing dir
  let result = (R._root .~ dir) <$> cs
  -- TODO: do this somewhere more appropriate
  -- lift $ fromAff $ memoizeCompletionStrs dir result
  pure result

transitiveChildren
  ∷ ∀ f m
  . (Parallel f m, QuasarDSL m)
  ⇒ DirPath
  → m (Either QError (Array R.Resource))
transitiveChildren start = runExceptT do
  rs ← ExceptT $ children start
  cs ← parTraverse go rs
  pure $ rs <> join cs
  where
  go :: R.Resource → ExceptT QError m (Array R.Resource)
  go r = case R.getPath r of
    Left dir → do
      crs ← ExceptT $ transitiveChildren dir
      pure $ [r] <> crs
    Right _ → pure [r]

listing
  ∷ ∀ m
  . (Functor m, QuasarDSL m)
  ⇒ DirPath
  → m (Either QError (Array R.Resource))
listing p =
  map (map toResource) <$> liftQuasar (QF.dirMetadata p)
  where
  toResource ∷ QFS.Resource → R.Resource
  toResource res = case res of
    QFS.File path → R.File path
    QFS.Directory path →
      let workspaceName
            = S.stripSuffix (S.Pattern $ "." <> Config.workspaceExtension)
            ∘ P.runDirName =<< P.dirName path
      in case workspaceName of
        Just name → R.Workspace (p </> P.dir name)
        Nothing → R.Directory path
    QFS.Mount m → R.Mount $ either R.Database R.View $ QFSM.getPath m

-- | Generates a new resource name based on a directory path and a name for the
-- | resource. If the name already exists in the path a number is appended to
-- | the end of the name.
getNewName
  ∷ ∀ m
  . (Monad m, QuasarDSL m)
  ⇒ DirPath
  → String
  → m (Either QError String)
getNewName parent name = do
  result ← liftQuasar (QF.dirMetadata parent)
  pure case result of
    Right items
      | exists name items → Right (getNewName' items 1)
      | otherwise → Right name
    Left QF.NotFound → Right name
    Left err → Left err
  where

  getNewName' ∷ Array QFS.Resource → Int → String
  getNewName' items i =
    let arr = S.split (S.Pattern ".") name
    in fromMaybe "" do
      body ← Arr.head arr
      suffixes ← Arr.tail arr
      let newName = S.joinWith "." $ Arr.cons (body <> " " <> show i) suffixes
      pure if exists newName items
           then getNewName' items (i + one)
           else newName

  exists ∷ String → Array QFS.Resource → Boolean
  exists n = F.any ((_ == n) ∘ printName ∘ QR.getName)

  printName ∷ Either (Maybe P.DirName) P.FileName → String
  printName = either (fromMaybe "" ∘ map P.runDirName) P.runFileName

-- | Will return `Just` in case the resource was successfully moved, and
-- | `Nothing` in case no resource existed at the requested source path.
move
  ∷ ∀ f m
  . (Monad m, QuasarDSL m, Parallel f m)
  ⇒ R.Resource
  → AnyPath
  → m (Either QError (Maybe AnyPath))
move src tgt = do
  let
    srcPath = R.getPath src

  runExceptT ∘ traverse cleanViewMounts $ srcPath ^? _Left

  runExceptT case src of
    R.Workspace wsDir → replacePathsInDecks wsDir
    _ → pure unit

  result ←
    case src of
      R.Mount _ → liftQuasar $ QF.moveMount srcPath tgt
      _ → liftQuasar $ QF.moveData srcPath tgt

  pure
    case result of
      Right _ → Right (Just tgt)
      Left QF.NotFound → Right Nothing
      Left err → Left err

  where
  exceptTHead ∷ ∀ a. String → Array a → ExceptT QError m a
  exceptTHead msg arr = case Arr.head arr of
    Nothing → throwError $ Error $ error msg
    Just a → pure a

  replacePathsInDecks ∷ DirPath → ExceptT QError m Unit
  replacePathsInDecks wsDir = do
    mbDid ← getWorkspaceRoot wsDir
    for_ mbDid \did → do
      deck ← getDeck wsDir did
      (save × newDeck) ← oneDeck wsDir deck
      when save $ putDeck wsDir did newDeck

  getWorkspaceRoot ∷ DirPath → ExceptT QError m (Maybe DID.DeckId)
  getWorkspaceRoot wsDir = do
    wsIndexArr ←
      ExceptT $ liftQuasar $ QF.readFile QDJ.Readable (wsDir </> P.file "index") Nothing
    wmJS ← exceptTHead "incorrect workspace model" wsIndexArr
    deck ← ExceptT $ pure $ lmap (Error ∘ error) $ WM.decode wmJS
    pure deck.root

  getDeck ∷ DirPath → DID.DeckId → ExceptT QError m DM.Deck
  getDeck wsDir did = do
    deckJArr ←
      ExceptT
        $ liftQuasar
        $ QF.readFile
          QDJ.Readable
          (wsDir </> P.dir (DID.deckIdToString did) </> P.file "index")
          Nothing
    deckJS ← exceptTHead "incorrect deck model" deckJArr
    ExceptT $ pure $ lmap (Error ∘ error) $ DM.decode deckJS

  putDeck ∷ DirPath → DID.DeckId → DM.Deck → ExceptT QError m Unit
  putDeck wsDir did deck = do
    ExceptT
      $ QD.save
        (wsDir </> P.dir (DID.deckIdToString did) </> P.file "index")
        (J.encodeJson $ Arr.singleton $ DM.encode deck)

  oneDeck ∷ DirPath → DM.Deck → ExceptT QError m (Boolean × DM.Deck)
  oneDeck wsDir deck =
    let
      replaceCardModel ∷ CM.Model → DM.Deck → DM.Deck
      replaceCardModel card@{cardId} d =
        d { cards =
               Arr.sortBy (\{cardId: a} {cardId: b} → compare a b)
               $ Arr.cons card
               $ Arr.filter (not ∘ eq cardId ∘ _.cardId) d.cards
          }

--      bi ∷ ∀ a b c d f. Bifunctor f ⇒ (∀ a' → c') → f a b → f

      foldFn ∷ Boolean × DM.Deck → CM.Model → ExceptT QError m (Boolean × DM.Deck)
      foldFn current@(shouldSave × d) {cardId, model} = case model of
        CM.Draftboard m → do
          flip parTraverse_ (List.catMaybes $ Pane.toList m.layout) \did → do
            d' ← getDeck wsDir  did
            (save × newDeck) ← oneDeck wsDir d'
            when save $ putDeck wsDir did d'
          pure current
        CM.Cache m →
          let
            newM =
              S.replace
                (S.Pattern $ P.printPath wsDir)
                (S.Replacement $ either P.printPath P.printPath tgt)
                <$> m
            newCard = {cardId, model: CM.Cache newM}
          in
            pure $ true × replaceCardModel newCard deck
        CM.Open mbR →
          let
            newMbR = do
              r ← mbR
              rel ←
                bisequence
                  $ bimap (flip P.relativeTo wsDir) (flip P.relativeTo wsDir) r
              tgtDir ← either (const Nothing) Just tgt
              let
                newP =
                  bimap P.canonicalize P.canonicalize
                  $ bimap (tgtDir </> _) (tgtDir </> _) rel
              pure $ R.setPath r newP
            newCard = {cardId, model: CM.Open newMbR}
          in
            pure $ (newMbR ≠ mbR) × replaceCardModel newCard deck
        _ → pure current
    in Arr.foldM foldFn (false × deck) deck.cards

delete
  ∷ ∀ f m
  . (Monad m, QuasarDSL m, Parallel f m)
  ⇒ R.Resource
  → m (Either QError (Maybe R.Resource))
delete resource =
  runExceptT $
    if R.isMount resource || alreadyInTrash resource
    then
      forceDelete resource $> Nothing
    else
      moveToTrash resource `catchError` \(err ∷ QError) →
        forceDelete resource $> Nothing

  where
  msg ∷ String
  msg = "cannot delete"

  moveToTrash
    ∷ R.Resource
    → ExceptT QError m (Maybe R.Resource)
  moveToTrash res = do
    let
      d = (res ^. R._root) </> P.dir Config.trashFolder
      path = (res # R._root .~ d) ^. R._path
    name ← ExceptT $ getNewName d (res ^. R._name)
    ExceptT $ move res (path # R._nameAnyPath .~ name)
    pure ∘ Just $ R.Directory d

  alreadyInTrash ∷ R.Resource → Boolean
  alreadyInTrash res =
    case res ^. R._path of
      Left path → alreadyInTrash' path
      Right _ → alreadyInTrash' (res ^. R._root)

  alreadyInTrash' ∷ DirPath → Boolean
  alreadyInTrash' d =
    if d == P.rootDir
    then false
    else maybe false go $ P.peel d

    where
    go ∷ Tuple DirPath (Either P.DirName P.FileName) → Boolean
    go (Tuple d' name) =
      case name of
        Right _ → false
        Left n →
          if n == P.DirName Config.trashFolder
          then true
          else alreadyInTrash' d'

forceDelete
  ∷ ∀ f m
  . (QuasarDSL m, Parallel f m)
  ⇒ R.Resource
  → ExceptT QError m Unit
forceDelete res =
  case res of
    R.Mount _ →
      ExceptT ∘ liftQuasar $ QF.deleteMount (R.getPath res)
    _ → do
      let path = R.getPath res
      traverse cleanViewMounts $ path ^? _Left
      ExceptT ∘ liftQuasar $ QF.deleteData path

cleanViewMounts
  ∷ ∀ f m
  . (Parallel f m, QuasarDSL m)
  ⇒ DirPath
  → ExceptT QError m Unit
cleanViewMounts =
  parTraverse_ deleteViewMount <=< ExceptT ∘ transitiveChildren
  where
  deleteViewMount ∷ R.Resource → ExceptT QError m Unit
  deleteViewMount =
    case _ of
      R.Mount (R.View vp) →
        ExceptT ∘ liftQuasar $ QF.deleteMount (Right vp)
      _ → pure unit

messageIfFileNotFound
  ∷ ∀ m
  . (Functor m, QuasarDSL m)
  ⇒ FilePath
  → String
  → m (Either QError (Maybe String))
messageIfFileNotFound path defaultMsg =
  handleResult <$> liftQuasar (QF.fileMetadata path)
  where
  handleResult ∷ ∀ a. Either QF.QError a → Either QError (Maybe String)
  handleResult (Left QF.NotFound) = Right (Just defaultMsg)
  handleResult (Left err) = Left err
  handleResult (Right _) = Right Nothing


dirNotAccessible
  ∷ ∀ m
  . (Functor m, QuasarDSL m)
  ⇒ DirPath
  → m (Maybe QF.QError)
dirNotAccessible path =
  either Just (const Nothing) <$> liftQuasar (QF.dirMetadata path)

fileNotAccessible
  ∷ ∀ m
  . (Functor m, QuasarDSL m)
  ⇒ FilePath
  → m (Maybe QF.QError)
fileNotAccessible path =
  either Just (const Nothing) <$> liftQuasar (QF.fileMetadata path)
