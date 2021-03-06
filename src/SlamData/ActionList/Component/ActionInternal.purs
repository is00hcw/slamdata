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

module SlamData.ActionList.Component.ActionInternal where

import SlamData.Prelude

import SlamData.ActionList.Action (ActionDescription, ActionHighlighted, ActionIconSrc)

data ActionInternal a
  = DoInternal (Array ActionNameWord) ActionIconSrc ActionDescription ActionHighlighted a
  | DrillInternal (Array ActionNameWord) ActionIconSrc ActionDescription (Array (ActionInternal a))
  | GoBackInternal

derive instance eqActionInternal ∷ Eq a ⇒ Eq (ActionInternal a)

newtype ActionNameWord = ActionNameWord { word ∷ String, widthPx ∷ Number }

derive instance eqActionNameWord ∷ Eq ActionNameWord

type Dimensions = { width ∷ Number, height ∷ Number }

type ButtonMetrics =
  { dimensions ∷ Dimensions
  , iconDimensions ∷ Dimensions
  , iconMarginPx ∷ Number
  , iconOnlyLeftPx ∷ Number
  , iconOnlyTopPx ∷ Number
  }

data Presentation
  = IconOnly
  | TextOnly
  | IconAndText

newtype ActionNameLine = ActionNameLine { line ∷ String, widthPx ∷ Number }
