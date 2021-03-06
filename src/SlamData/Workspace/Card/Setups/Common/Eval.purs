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

module SlamData.Workspace.Card.Setups.Chart.Common.Eval
  ( buildChartEval
  , buildChartEval'
  , analyze
  , type (>>)
  ) where

import SlamData.Prelude

import Control.Monad.State (class MonadState, get, put)
import Control.Monad.Throw (class MonadThrow)

import Data.Argonaut (Json)
import Data.Array as A
import Data.Lens ((^.))
import Data.Map as M

import ECharts.Monad (DSL)
import ECharts.Types.Phantom (OptionI)

import SlamData.Quasar.Class (class QuasarDSL)
import SlamData.Quasar.Query as QQ
import SlamData.Workspace.Card.Setups.Axis (Axes, buildAxes)
import SlamData.Workspace.Card.CardType.ChartType (ChartType)
import SlamData.Workspace.Card.Eval.Monad as CEM
import SlamData.Workspace.Card.Port as Port

infixr 3 type M.Map as >>

buildChartEval
  ∷ ∀ m p
  . ( MonadState CEM.CardState m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ ChartType
  → (Axes → p → Array Json → DSL OptionI)
  → Maybe p
  → Port.Resource
  → m Port.Port
buildChartEval chartType build model =
  flip buildChartEval' model
    \axes model' records →
      Port.ChartInstructions
        { options: build axes model' records
        , chartType
        }

buildChartEval'
  ∷ ∀ m p
  . ( MonadState CEM.CardState m
    , MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ (Axes → p → Array Json → Port.Port)
  → Maybe p
  → Port.Resource
  → m Port.Port
buildChartEval' build model resource = do
  records × axes ← analyze resource =<< get
  put (Just (CEM.Analysis { resource, records, axes }))
  case model of
    Just ch → pure $ build axes ch records
    Nothing → CEM.throw "Please select an axis."

analyze
  ∷ ∀ m
  . ( MonadThrow CEM.CardError m
    , QuasarDSL m
    )
  ⇒ Port.Resource
  → CEM.CardState
  → m (Array Json × Axes)
analyze resource = case _ of
  Just (CEM.Analysis st) | resource ≡ st.resource →
    pure (st.records × st.axes)
  _ → do
    records ← CEM.liftQ (QQ.all (resource ^. Port._filePath))
    let axes = buildAxes (A.take 300 records)
    pure (records × axes)
