-- | Primitive parsers for working with an input stream of type `String`.

module Text.Parsing.Parser.String where


import Data.String as S
import Control.Monad.State (modify, gets)
import Data.Array (many, toUnfoldable)
import Data.Foldable (fold, elem, notElem)
import Data.Newtype (class Newtype, unwrap)
import Data.Unfoldable (class Unfoldable)
import Data.List as L
import Data.Monoid.Endo (Endo(..))
import Data.Maybe (Maybe(..))
import Data.Monoid (class Monoid)
import Text.Parsing.Parser (ParseState(..), ParserT, fail)
import Text.Parsing.Parser.Combinators (try, (<?>))
import Text.Parsing.Parser.Pos (Position, updatePosString, updatePosChar)
import Prelude hiding (between)

-- | A newtype used in cases where there is a prefix to be droped.
newtype Prefix a = Prefix a

derive instance eqPrefix :: (Eq a) => Eq (Prefix a)
derive instance ordPrefix :: (Ord a) => Ord (Prefix a)
derive instance newtypePrefix :: Newtype (Prefix a) _

instance showPrefix :: (Show a) => Show (Prefix a) where
  show (Prefix s) = "(Prefix " <> show s <> ")"

class HasUpdatePosition a where
  updatePos :: Position -> a -> Position

instance stringHasUpdatePosition :: HasUpdatePosition String where
  updatePos = updatePosString

instance charHasUpdatePosition :: HasUpdatePosition Char where
  updatePos = updatePosChar

-- | This class exists to abstract over streams which support the string-like
-- | operations which this modules needs.
-- |
-- | Instances must satisfy the following laws:
-- |
class StreamLike f c | f -> c where
  uncons :: f -> Maybe { head :: c, tail :: f, updatePos :: Position -> Position }
  drop :: Prefix f -> f -> Maybe {  rest :: f, updatePos :: Position -> Position }

instance stringStreamLike :: StreamLike String Char where
  uncons f = S.uncons f <#> \({ head, tail}) ->
    { head, tail, updatePos: (_ `updatePos` head)}
  drop (Prefix p) s = S.stripPrefix (S.Pattern p) s <#> \rest ->
    { rest, updatePos: (_ `updatePos` p)}

instance listcharStreamLike :: (Eq a, HasUpdatePosition a) => StreamLike (L.List a) a where
  uncons f = L.uncons f <#> \({ head, tail}) ->
    { head, tail, updatePos: (_ `updatePos` head)}
  drop (Prefix p) s = L.stripPrefix (L.Pattern p) s <#> \rest ->
    { rest, updatePos: unwrap (fold (p <#> (flip updatePos >>> Endo)))}

eof :: forall f c m. StreamLike f c => Monad m => ParserT f m Unit
eof = do
  input <- gets \(ParseState input _ _) -> input
  case uncons input of
    Nothing -> pure unit
    _ -> fail "Expected EOF"

-- | Match the specified string.
string :: forall f c m. StreamLike f c => Show f => Monad m => f -> ParserT f m f
string str = do
  input <- gets \(ParseState input _ _) -> input
  case drop (Prefix str) input of
    Just {rest, updatePos} -> do
      modify \(ParseState _ position _) ->
        ParseState rest (updatePos position) true
      pure str
    _ -> fail ("Expected " <> show str)

-- | Match any character.
anyChar :: forall f c m. StreamLike f c => Monad m => ParserT f m c
anyChar = do
  input <- gets \(ParseState input _ _) -> input
  case uncons input of
    Nothing -> fail "Unexpected EOF"
    Just ({ head, updatePos, tail }) -> do
      modify \(ParseState _ position _) ->
        ParseState tail (updatePos position) true
      pure head

-- | Match a character satisfying the specified predicate.
satisfy :: forall f c m. StreamLike f c => Show c => Monad m => (c -> Boolean) -> ParserT f m c
satisfy f = try do
  c <- anyChar
  if f c then pure c
         else fail $ "Character " <> show c <> " did not satisfy predicate"

-- | Match the specified character
char :: forall f c m. StreamLike f c => Eq c => Show c => Monad m => c -> ParserT f m c
char c = satisfy (_ == c) <?> ("Expected " <> show c)

-- | Match many whitespace characters.
whiteSpace :: forall f m g. StreamLike f Char => Unfoldable g => Monoid f => Monad m => ParserT f m (g Char)
whiteSpace = map toUnfoldable whiteSpace'

-- | Match a whitespace characters but returns them as Array.
whiteSpace' :: forall f m. StreamLike f Char => Monad m => ParserT f m (Array Char)
whiteSpace' = many $ satisfy \c -> c == '\n' || c == '\r' || c == ' ' || c == '\t'

-- | Skip whitespace characters.
skipSpaces :: forall f m. StreamLike f Char => Monad m => ParserT f m Unit
skipSpaces = void whiteSpace'

-- | Match one of the characters in the array.
oneOf :: forall f c m. StreamLike f c => Show c => Eq c => Monad m => Array c -> ParserT f m c
oneOf ss = satisfy (flip elem ss) <?> ("one of " <> show ss)

-- | Match any character not in the array.
noneOf :: forall f c m. StreamLike f c => Show c => Eq c => Monad m => Array c -> ParserT f m c
noneOf ss = satisfy (flip notElem ss) <?> ("none of " <> show ss)
