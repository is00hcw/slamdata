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

module SlamData.Workspace.Card.Setups.FormInput.Date.Component
  ( dateSetupComponent
  ) where

import Halogen as H

import SlamData.Monad (Slam)
import SlamData.Workspace.Card.CardType.FormInputType as FIT
import SlamData.Workspace.Card.Component as CC
import SlamData.Workspace.Card.Component.State as CCS
import SlamData.Workspace.Card.Component.Query as CCQ
import SlamData.Workspace.Card.Setups.FormInput.TextLike.Component (textLikeSetupComponent)

dateSetupComponent ∷ CC.CardOptions → H.Component CC.CardStateP CC.CardQueryP Slam
dateSetupComponent =
  textLikeSetupComponent
    FIT.Date
    { _State: CCS._SetupDateState
    , _Query: CC.makeQueryPrism' CCQ._SetupDateQuery
    , valueProjection: \ax →
        ax.date
    }
