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

module SlamData.Workspace.Card.Setups.Chart.Funnel.Component.State where

import SlamData.Prelude

import Data.Argonaut (JCursor)
import Data.Lens (Lens', lens)

import Halogen (ParentState)

import SlamData.Monad (Slam)
import SlamData.Common.Align (Align)
import SlamData.Common.Sort (Sort)
import SlamData.Form.Select (Select, emptySelect)
import SlamData.Workspace.LevelOfDetails (LevelOfDetails(..))
import SlamData.Workspace.Card.Setups.Chart.Funnel.Component.ChildSlot as CS
import SlamData.Workspace.Card.Setups.Chart.Funnel.Component.Query (QueryC, Selection)
import SlamData.Workspace.Card.Setups.Chart.Aggregation (Aggregation)
import SlamData.Workspace.Card.Setups.Axis (Axes, initialAxes)
import SlamData.Workspace.Card.Setups.Inputs (PickerOptions)

type State =
  { axes ∷ Axes
  , levelOfDetails ∷ LevelOfDetails
  , category ∷ Select JCursor
  , value ∷ Select JCursor
  , valueAgg ∷ Select Aggregation
  , series ∷ Select JCursor
  , align ∷ Select Align
  , order ∷ Select Sort
  , picker ∷ Maybe (PickerOptions JCursor Selection)
  }

initialState ∷ State
initialState =
  { axes: initialAxes
  , levelOfDetails: High
  , category: emptySelect
  , value: emptySelect
  , valueAgg: emptySelect
  , series: emptySelect
  , align: emptySelect
  , order: emptySelect
  , picker: Nothing
  }

type StateP =
  ParentState State CS.ChildState QueryC CS.ChildQuery Slam CS.ChildSlot

_category ∷ ∀ a r. Lens' { category ∷ a | r } a
_category = lens _.category _{ category = _ }

_value ∷ ∀ a r. Lens' { value ∷ a | r } a
_value = lens _.value _{ value = _ }

_valueAgg ∷ ∀ a r. Lens' { valueAgg ∷ a | r } a
_valueAgg = lens _.valueAgg _{ valueAgg = _ }

_series ∷ ∀ a r. Lens' { series ∷ a | r } a
_series = lens _.series _{ series = _ }

_align ∷ ∀ a r. Lens' { align ∷ a | r } a
_align = lens _.align _{ align = _ }

_order ∷ ∀ a r. Lens' { order ∷ a | r } a
_order = lens _.order _{ order = _ }

showPicker
  ∷ (Const Unit JCursor → Selection (Const Unit))
  → Array JCursor
  → State
  → State
showPicker f options =
  _ { picker = Just { options, select: f (Const unit) } }
