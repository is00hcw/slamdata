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

module SlamData.Workspace.Card.Setups.FormInput.Static.Component.State where

import SlamData.Prelude

import Data.Argonaut (JCursor)
import Data.Lens (Lens', lens)

import Halogen (ParentState)

import SlamData.Monad (Slam)
import SlamData.Form.Select (Select, emptySelect)
import SlamData.Workspace.LevelOfDetails (LevelOfDetails(..))
import SlamData.Workspace.Card.Setups.FormInput.Static.Component.ChildSlot as CS
import SlamData.Workspace.Card.Setups.FormInput.Static.Component.Query (QueryC, Selection)
import SlamData.Workspace.Card.Setups.Axis (Axes, initialAxes)
import SlamData.Workspace.Card.Setups.Inputs (PickerOptions)

type State =
  { axes ∷ Axes
  , levelOfDetails ∷ LevelOfDetails
  , picker ∷ Maybe (PickerOptions JCursor Selection)
  , value ∷ Select JCursor
  }

initialState ∷ State
initialState =
  { axes: initialAxes
  , levelOfDetails: High
  , picker: Nothing
  , value: emptySelect
  }

type StateP =
  ParentState State CS.ChildState QueryC CS.ChildQuery Slam CS.ChildSlot

_value ∷ ∀ r a. Lens' { value ∷ a | r } a
_value = lens _.value _ { value = _ }

showPicker
  ∷ (Const Unit JCursor → Selection (Const Unit))
  → Array JCursor
  → State
  → State
showPicker f options =
  _ { picker = Just { options, select: f (Const unit) } }
