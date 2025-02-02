module Halogen.Form.Injective where

import Prologue

import Control.Bind (bindFlipped)
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Bifunctor (bimap)
import Data.Identity (Identity(..))
import Data.Lens (preview)
import Data.List (List)
import Data.List.Lazy as LL
import Data.List.Lazy.NonEmpty as LLNE
import Data.List.NonEmpty (NonEmptyList)
import Data.Map (Map)
import Data.Map as Map
import Data.Newtype (unwrap)
import Data.Profunctor.Choice ((+++))
import Data.Profunctor.Star (Star(..))
import Data.Profunctor.Strong ((***))
import Data.Set (Set)
import Data.Set as Set
import Data.Symbol (class IsSymbol)
import Data.Traversable (class Traversable, traverse)
import Halogen.Form.FieldState (FieldState(..), _Complete)
import Prim.Row as Row
import Prim.RowList (class RowToList, RowList)
import Prim.RowList as RL
import Record as Record
import Record.Builder (Builder)
import Record.Builder as Builder
import Type.Proxy (Proxy(..))

-- | Class for projecting a result from a structure. Laws:
-- |
-- | ```
-- | project (inject r) == Just r
-- | r /= r => inject r /= inject r
-- | map inject (project a) == a
-- | project blank == Nothing
-- | blank /= inject r
-- | ```
class Injective r a | a -> r where
  blank :: a
  project :: a -> Maybe r
  inject :: r -> a

instance Injective output (FieldState input output) where
  blank = Blank
  project = preview _Complete
  inject = Complete

instance
  ( Injective r1 a
  , Injective r2 b
  ) =>
  Injective (Tuple r1 r2) (Tuple a b) where
  blank = Tuple blank blank
  project = unwrap $ (Star project) *** (Star project)
  inject = bimap inject inject

instance
  ( Injective r1 a
  , Injective r2 b
  ) =>
  Injective (Either r1 r2) (Either a b) where
  blank = Left blank
  project = unwrap $ (Star project) +++ (Star project)
  inject = bimap inject inject

instance Injective r a => Injective r (Identity a) where
  blank = Identity blank
  project = project <<< unwrap
  inject = Identity <<< inject

instance Injective r a => Injective r (Maybe a) where
  blank = Nothing
  project = bindFlipped project
  inject = Just <<< inject

instance Injective r a => Injective (Array r) (Array a) where
  blank = mempty
  project = traversableProject
  inject = functorInject

instance Injective r a => Injective (List r) (List a) where
  blank = mempty
  project = traversableProject
  inject = functorInject

instance Injective r a => Injective (LL.List r) (LL.List a) where
  blank = mempty
  project = traversableProject
  inject = functorInject

instance Injective r a => Injective (NonEmptyArray r) (NonEmptyArray a) where
  blank = pure blank
  project = traversableProject
  inject = functorInject

instance Injective r a => Injective (NonEmptyList r) (NonEmptyList a) where
  blank = pure blank
  project = traversableProject
  inject = functorInject

instance
  Injective r a =>
  Injective (LLNE.NonEmptyList r) (LLNE.NonEmptyList a) where
  blank = pure blank
  project = traversableProject
  inject = functorInject

instance (Ord r, Ord a, Injective r a) => Injective (Set r) (Set a) where
  blank = mempty
  project =
    map (Set.fromFoldable :: Array r -> Set r)
      <<< traversableProject
      <<< Set.toUnfoldable
  inject = Set.map inject

instance Injective r a => Injective (Map k r) (Map k a) where
  blank = Map.empty
  project = traversableProject
  inject = functorInject

traversableProject
  :: forall t r a. Injective r a => Traversable t => t a -> Maybe (t r)
traversableProject = traverse project

functorInject
  :: forall f r a. Injective r a => Functor f => f r -> f a
functorInject = map inject

class
  ProjectiveRecord (rl :: RowList Type) rip rii rop roi
  | rl -> rip rii rop roi where
  blankRecord :: Proxy rl -> Builder {} { | rii }
  projectRecord :: Proxy rl -> { | rip } -> Maybe (Builder {} { | rop })
  injectRecord :: Proxy rl -> { | roi } -> Builder {} { | rii }

instance
  ( IsSymbol label
  , Row.Lacks label rop'
  , Row.Lacks label rii'
  , Row.Cons label a rip' rip
  , Row.Cons label a rii' rii
  , Row.Cons label r rop' rop
  , Row.Cons label r roi' roi
  , ProjectiveRecord rl rip rii' rop' roi
  , Injective r a
  ) =>
  ProjectiveRecord (RL.Cons label a rl) rip rii rop roi where
  blankRecord _ =
    Builder.insert (Proxy :: _ label) blank <<< blankRecord (Proxy :: _ rl)
  projectRecord _ ri =
    (compose <<< Builder.insert label)
      <$> project (Record.get label ri)
      <*> projectRecord (Proxy :: _ rl) ri
    where
    label = Proxy :: _ label
  injectRecord _ roi =
    Builder.insert label (inject $ Record.get label roi)
      <<< injectRecord (Proxy :: _ rl) roi
    where
    label = Proxy :: _ label

-- | This instance is unlawful, it does not satisfy the laws:
-- | ```
-- | project blank == Nothing
-- | blank /= inject r
-- | ```
-- | It is still necessary to get records in generat to compile.
instance ProjectiveRecord RL.Nil rip () () roi where
  blankRecord _ = identity
  projectRecord _ _ = pure identity
  injectRecord _ _ = identity

instance
  ( RowToList ri rl
  , ProjectiveRecord rl ri ri ro ro
  ) =>
  Injective { | ro } { | ri } where
  blank = Builder.buildFromScratch $ blankRecord (Proxy :: _ rl)
  project ri = Builder.buildFromScratch <$> projectRecord (Proxy :: _ rl) ri
  inject = Builder.buildFromScratch <<< injectRecord (Proxy :: _ rl)
