module SlamData.Workspace.Card.Next.Component
 ( nextCardComponent
 , module SlamData.Workspace.Card.Next.Component.State
 , module SlamData.Workspace.Card.Next.Component.Query
 ) where

import SlamData.Prelude

import Data.Array as Arr
import Data.Argonaut (jsonEmptyObject)
import Data.Lens ((.~))

import Halogen as H
import Halogen.HTML.Events.Indexed as HE
import Halogen.HTML.Indexed as HH
import Halogen.HTML.Properties.Indexed as HP
import Halogen.HTML.Properties.Indexed.ARIA as ARIA
import Halogen.Themes.Bootstrap3 as B

import SlamData.Effects (Slam)
import SlamData.Workspace.Card.CardType as Ct
import SlamData.Workspace.Card.Common.EvalQuery as Ec
import SlamData.Workspace.Card.Component (makeCardComponent, makeQueryPrism, _NextState, _NextQuery)
import SlamData.Workspace.Card.Component as Cc
import SlamData.Workspace.Card.Next.Component.Query (QueryP, Query(AddCard, SetAvailableTypes, SetMessage), _AddCardType)
import SlamData.Workspace.Card.Next.Component.State (State, _message, _types, initialState)

type NextHTML = H.ComponentHTML QueryP
type NextDSL = H.ComponentDSL State QueryP Slam

nextCardComponent :: Cc.CardComponent
nextCardComponent = makeCardComponent
  { cardType: Ct.NextAction
  , component: H.component {render, eval}
  , initialState: initialState
  , _State: _NextState
  , _Query: makeQueryPrism _NextQuery
  }

render :: State → NextHTML
render state =
  case state.message of
    Nothing →
      HH.ul_
        $ map nextButton state.types
        ⊕ map disabledButton (Ct.insertableCardTypes Arr.\\ state.types)

    Just msg →
      HH.div
        [ HP.classes [ B.alert, B.alertInfo ] ]
        [ HH.h4_ [ HH.text msg ] ]
  where
  cardTitle ∷ Ct.CardType → String
  cardTitle cty = "Insert " ⊕ Ct.cardName cty ⊕ " card"

  disabledTitle ∷ Ct.CardType → String
  disabledTitle cty = Ct.cardName cty ⊕ " is unavailable as next action"

  nextButton ∷ Ct.CardType → NextHTML
  nextButton cty =
    HH.li_
      [ HH.button
          [ HP.title $ cardTitle cty
          , ARIA.label $ cardTitle cty
          , HE.onClick (HE.input_ (right ∘ AddCard cty))
          ]
          [ Ct.cardGlyph cty
          , HH.p_ [ HH.text (Ct.cardName cty) ]
          ]
      ]

  disabledButton ∷ Ct.CardType → NextHTML
  disabledButton cty =
    HH.li_
      [ HH.button
          [ HP.title $ disabledTitle cty
          , ARIA.label $ disabledTitle cty
          , HP.disabled true
          ]
          [ Ct.cardGlyph cty
          , HH.p_ [ HH.text (Ct.cardName cty) ]
          ]
      ]

eval :: QueryP ~> NextDSL
eval = coproduct cardEval nextEval

cardEval :: Ec.CardEvalQuery ~> NextDSL
cardEval (Ec.EvalCard _ k) = map k ∘ Ec.runCardEvalT $ pure Nothing
cardEval (Ec.NotifyRunCard next) = pure next
cardEval (Ec.NotifyStopCard next) = pure next
cardEval (Ec.Save k) = pure $ k jsonEmptyObject
cardEval (Ec.Load _ next) = pure next
cardEval (Ec.SetupCard p next) = pure next
cardEval (Ec.SetCanceler _ next) = pure next

nextEval :: Query ~> NextDSL
nextEval (AddCard _ next) = pure next
nextEval (SetAvailableTypes cts next) = H.modify (_types .~ cts) $> next
nextEval (SetMessage mbTxt next) = H.modify (_message .~ mbTxt) $> next