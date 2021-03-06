{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE CPP #-}
#if defined(__GLASGOW_HASKELL__) && __GLASGOW_HASKELL__ >= 702
{-# LANGUAGE Trustworthy #-}
#endif
----------------------------------------------------------------------------
-- |
-- Module     : Data.Functor.Trans.Tagged
-- Copyright  : 2011-2013 Edward Kmett
-- License    : BSD3
--
-- Maintainer  : Edward Kmett <ekmett@gmail.com>
-- Stability   : experimental
-- Portability : portable
--
-------------------------------------------------------------------------------

module Data.Functor.Trans.Tagged
  (
  -- * Tagged values
    TaggedT(..)
  , tag, untag
  , retag
  , mapTaggedT
  , reflected, reflectedM
  , asTaggedTypeOf
  ) where

#if defined(__GLASGOW_HASKELL__) && (__GLASGOW_HASKELL__ >= 706)
import Prelude hiding (foldr, foldl, mapM, sequence, foldr1, foldl1)
#else
import Prelude hiding (catch, foldr, foldl, mapM, sequence, foldr1, foldl1)
#endif
import Control.Applicative (Alternative(..), Applicative(..), (<$), (<$>))
import Control.Monad (liftM, MonadPlus(..))
import Control.Monad.Catch (MonadCatch(..))
import Control.Monad.Fix (MonadFix(..))
import Control.Monad.Trans (MonadIO(..), MonadTrans(..))
import Control.Monad.Reader (MonadReader(..))
import Control.Monad.Writer (MonadWriter(..))
import Control.Monad.State (MonadState(..))
import Control.Monad.Cont (MonadCont(..))
import Control.Comonad.Trans.Class (ComonadTrans(..))
import Control.Comonad.Hoist.Class (ComonadHoist(..))
import Control.Comonad (Comonad(..))
import Data.Traversable (Traversable(..))
import Data.Foldable (Foldable(..))
import Data.Distributive (Distributive(..))
import Data.Functor.Bind (Apply(..), Bind(..))
import Data.Functor.Extend (Extend(..))
import Data.Functor.Plus (Alt(..), Plus(..))
import Data.Functor.Contravariant (Contravariant(..))
import Data.Proxy (Proxy(..))
import Data.Reflection (Reifies(..))

-- | A @'Tagged' s b@ value is a value @b@ with an attached phantom type @s@.
-- This can be used in place of the more traditional but less safe idiom of
-- passing in an undefined value with the type, because unlike an @(s -> b)@,
-- a @'Tagged' s b@ can't try to use the argument @s@ as a real value.
--
-- Moreover, you don't have to rely on the compiler to inline away the extra
-- argument, because the newtype is \"free\"

newtype TaggedT s m b = TagT { untagT :: m b }
  deriving ( Eq, Ord, Read, Show )

instance Functor m => Functor (TaggedT s m) where
  fmap f (TagT x) = TagT (fmap f x)
  {-# INLINE fmap #-}
  b <$ (TagT x) = TagT (b <$ x)
  {-# INLINE (<$) #-}

instance Contravariant m => Contravariant (TaggedT s m) where
  contramap f (TagT x) = TagT (contramap f x)
  {-# INLINE contramap #-}

instance Apply m => Apply (TaggedT s m) where
  TagT f <.> TagT x = TagT (f <.> x)
  {-# INLINE (<.>) #-}
  TagT f  .> TagT x = TagT (f  .> x)
  {-# INLINE ( .>) #-}
  TagT f <.  TagT x = TagT (f <.  x)
  {-# INLINE (<. ) #-}

instance Applicative m => Applicative (TaggedT s m) where
  pure = TagT . pure
  {-# INLINE pure #-}
  TagT f <*> TagT x = TagT (f <*> x)
  {-# INLINE (<*>) #-}
  TagT f  *> TagT x = TagT (f  *> x)
  {-# INLINE ( *>) #-}
  TagT f <*  TagT x = TagT (f <*  x)
  {-# INLINE (<* ) #-}

instance Bind m => Bind (TaggedT s m) where
  TagT m >>- k = TagT (m >>- untagT . k)
  {-# INLINE (>>-) #-}

instance Monad m => Monad (TaggedT s m) where
  return = TagT . return
  {-# INLINE return #-}
  TagT m >>= k = TagT (m >>= untagT . k)
  {-# INLINE (>>=) #-}
  TagT m >> TagT n = TagT (m >> n)
  {-# INLINE (>>) #-}

instance Alt m => Alt (TaggedT s m) where
  TagT a <!> TagT b = TagT (a <!> b)
  {-# INLINE (<!>) #-}

instance Alternative m => Alternative (TaggedT s m) where
  empty = TagT empty
  {-# INLINE empty #-}
  TagT a <|> TagT b = TagT (a <|> b)
  {-# INLINE (<|>) #-}

instance Plus m => Plus (TaggedT s m) where
  zero = TagT zero
  {-# INLINE zero #-}

instance MonadPlus m => MonadPlus (TaggedT s m) where
  mzero = TagT mzero
  {-# INLINE mzero #-}
  mplus (TagT a) (TagT b) = TagT (mplus a b)
  {-# INLINE mplus #-}

instance MonadFix m => MonadFix (TaggedT s m) where
  mfix f = TagT $ mfix (untagT . f)
  {-# INLINE mfix #-}

instance MonadTrans (TaggedT s) where
  lift = TagT
  {-# INLINE lift #-}

instance MonadIO m => MonadIO (TaggedT s m) where
  liftIO = lift . liftIO
  {-# INLINE liftIO #-}

instance MonadWriter w m => MonadWriter w (TaggedT s m) where
#if MIN_VERSION_mtl(2,1,0)
  writer = lift . writer
  {-# INLINE writer #-}
#endif
  tell = lift . tell
  {-# INLINE tell #-}
  listen = lift . listen . untag
  {-# INLINE listen #-}
  pass = lift . pass . untag
  {-# INLINE pass #-}

instance MonadReader r m => MonadReader r (TaggedT s m) where
  ask = lift ask
  {-# INLINE ask #-}
  local f = lift . local f . untag
  {-# INLINE local #-}
#if MIN_VERSION_mtl(2,1,0)
  reader = lift . reader
  {-# INLINE reader #-}
#endif

instance MonadState t m => MonadState t (TaggedT s m) where
  get = lift get
  {-# INLINE get #-}
  put = lift . put
  {-# INLINE put #-}
#if MIN_VERSION_mtl(2,1,0)
  state = lift . state
  {-# INLINE state #-}
#endif

instance MonadCont m => MonadCont (TaggedT s m) where
  callCC f = lift . callCC $ \k -> untag (f (tag . k))
  {-# INLINE callCC #-}

instance Foldable f => Foldable (TaggedT s f) where
  foldMap f (TagT x) = foldMap f x
  {-# INLINE foldMap #-}
  fold (TagT x) = fold x
  {-# INLINE fold #-}
  foldr f z (TagT x) = foldr f z x
  {-# INLINE foldr #-}
  foldl f z (TagT x) = foldl f z x
  {-# INLINE foldl #-}
  foldl1 f (TagT x) = foldl1 f x
  {-# INLINE foldl1 #-}
  foldr1 f (TagT x) = foldr1 f x
  {-# INLINE foldr1 #-}

instance Traversable f => Traversable (TaggedT s f) where
  traverse f (TagT x) = TagT <$> traverse f x
  {-# INLINE traverse #-}
  sequenceA (TagT x) = TagT <$> sequenceA x
  {-# INLINE sequenceA #-}
  mapM f (TagT x) = liftM TagT (mapM f x)
  {-# INLINE mapM #-}
  sequence (TagT x) = liftM TagT (sequence x)
  {-# INLINE sequence #-}

instance Distributive f => Distributive (TaggedT s f) where
  distribute = TagT . distribute . fmap untagT
  {-# INLINE distribute #-}

instance Extend f => Extend (TaggedT s f) where
  extended f (TagT w) = TagT (extended (f . TagT) w)
  {-# INLINE extended #-}

instance Comonad w => Comonad (TaggedT s w) where
  extract (TagT w) = extract w
  {-# INLINE extract #-}

instance ComonadTrans (TaggedT s) where
  lower (TagT w) = w
  {-# INLINE lower #-}

instance ComonadHoist (TaggedT s) where
  cohoist f = TagT . f . untagT
  {-# INLINE cohoist #-}

instance MonadCatch m => MonadCatch (TaggedT s m) where
  throwM e = lift $ throwM e
  {-# INLINE throwM #-}
  catch m f = tag (catch (untag m) (untag . f))
  {-# INLINE catch #-}
  mask a = tag $ mask $ \u -> untag (a $ q u)
    where q u = tag . u . untag
  {-# INLINE mask #-}
  uninterruptibleMask a = tag $ uninterruptibleMask $ \u -> untag (a $ q u)
    where q u = tag . u . untag
  {-# INLINE uninterruptibleMask#-}

-- | Easier to type alias for 'TagT'
tag :: m b -> TaggedT s m b
tag = TagT
{-# INLINE tag #-}

-- | Easier to type alias for 'untagT'
untag :: TaggedT s m b -> m b
untag = untagT
{-# INLINE untag #-}

-- | Some times you need to change the tag you have lying around.
-- Idiomatic usage is to make a new combinator for the relationship between the
-- tags that you want to enforce, and define that combinator using 'retag'.
--
-- > data Succ n
-- > retagSucc :: Tagged n a -> Tagged (Succ n) a
-- > retagSucc = retag
retag :: TaggedT s m b -> TaggedT t m b
retag = tag . untag
{-# INLINE retag #-}

-- | Lift an operation on underlying monad
mapTaggedT :: (m a -> n b) -> TaggedT s m a -> TaggedT s n b
mapTaggedT f = tag . f . untag
{-# INLINE mapTaggedT #-}

-- | Reflect reified value back in 'Applicative' context
reflected :: forall s m a. (Applicative m, Reifies s a) => TaggedT s m a
reflected = tag . pure . reflect $ (Proxy :: Proxy s)
{-# INLINE reflected #-}

-- | Reflect reified value back in 'Monad' context
reflectedM :: forall s m a. (Monad m, Reifies s a) => TaggedT s m a
reflectedM = tag . return . reflect $ (Proxy :: Proxy s)
{-# INLINE reflectedM #-}

-- | 'asTaggedTypeOf' is a type-restricted version of 'const'. It is usually used as an infix operator, and its typing forces its first argument (which is usually overloaded) to have the same type as the tag of the second.
asTaggedTypeOf :: s -> TaggedT s m b -> s
asTaggedTypeOf = const
{-# INLINE asTaggedTypeOf #-}
