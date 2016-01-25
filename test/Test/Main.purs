module Test.Main where

import Prelude

import Data.Argonaut.Core
import Data.Argonaut.Decode (decodeJson, DecodeJson, gDecodeJson, genericDecodeJson', argonautOptions)
import Data.Argonaut.Encode (encodeJson, EncodeJson, gEncodeJson, genericEncodeJson', argonautOptions)
import Data.Argonaut.Combinators ((:=), (~>), (?>>=), (.?))
import Data.Either
import Data.Tuple
import Data.Maybe
import Data.Array
import Data.Generic
import Data.Foldable (foldl)
import Data.List (toList, List(..))
import Control.Monad.Eff.Console
import qualified Data.StrMap as M

import Test.StrongCheck
import Test.StrongCheck.Gen
import Test.StrongCheck.Generic

genJNull :: Gen Json
genJNull = pure jsonNull

genJBool :: Gen Json
genJBool = fromBoolean <$> arbitrary

genJNumber :: Gen Json
genJNumber = fromNumber <$> arbitrary

genJString :: Gen Json
genJString = fromString <$> arbitrary

genJArray :: Size -> Gen Json
genJArray sz = fromArray <$> vectorOf sz (genJson $ sz - 1)

genJObject :: Size -> Gen Json
genJObject sz = do
  v <- vectorOf sz (genJson $ sz - 1)
  k <- vectorOf (length v) (arbitrary :: Gen AlphaNumString)
  return $  let f (AlphaNumString s) = s ++ "x"
                k' = f <$> k
            in  fromObject <<< M.fromList <<< toList <<< nubBy (\a b -> (fst a) == (fst b)) $ zipWith Tuple k' v

genJson :: Size -> Gen Json
genJson 0 = oneOf genJNull [genJBool, genJNumber, genJString]
genJson n = frequency (Tuple 1.0 genJNull) rest where
  rest = toList [Tuple 2.0 genJBool,
                 Tuple 2.0 genJNumber,
                 Tuple 3.0 genJString,
                 Tuple 1.0 (genJArray n),
                 Tuple 1.0 (genJObject n)]

newtype TestJson = TestJson Json

instance arbitraryTestJson :: Arbitrary TestJson where
  arbitrary = TestJson <$> sized genJson


prop_encode_then_decode :: TestJson -> Boolean
prop_encode_then_decode (TestJson json) =
  Right json == (decodeJson $ encodeJson $ json)

prop_decode_then_encode :: TestJson -> Boolean
prop_decode_then_encode (TestJson json) =
  let decoded = (decodeJson json) :: Either String Json in
  Right json == (decoded >>= (encodeJson >>> pure))


encodeDecodeCheck = do
  log "Showing small sample of JSON"
  showSample (genJson 10)

  log "Testing that any JSON can be encoded and then decoded"
  quickCheck' 20 prop_encode_then_decode

  log "Testing that any JSON can be decoded and then encoded"
  quickCheck' 20 prop_decode_then_encode

prop_assoc_builder_str :: Tuple String String -> Boolean
prop_assoc_builder_str (Tuple key str) =
  case (key := str) of
    Tuple k json ->
      (key == k) && (decodeJson json == Right str)

newtype Obj = Obj Json
unObj :: Obj -> Json
unObj (Obj j) = j

instance arbitraryObj :: Arbitrary Obj where
  arbitrary = Obj <$> (genJObject 5)


prop_assoc_append :: (Tuple (Tuple String TestJson) Obj) -> Boolean
prop_assoc_append (Tuple (Tuple key (TestJson val)) (Obj obj)) =
  let appended = assoc ~> obj
      assoc = Tuple key val
  in case toObject appended >>= M.lookup key of
    Just val -> true
    _ -> false


prop_get_jobject_field :: Obj -> Boolean
prop_get_jobject_field (Obj obj) =
  maybe false go $ toObject obj
  where
  go :: JObject -> Boolean
  go obj =
    let keys = M.keys obj
    in foldl (\ok key -> ok && (isJust $ M.lookup key obj)) true keys

assert_maybe_msg :: Boolean
assert_maybe_msg =
  (isLeft (Nothing ?>>= "Nothing is Left"))
  &&
  ((Just 2 ?>>= "Nothing is left") == Right 2)




combinatorsCheck = do
  log "Check assoc builder `:=`"
  quickCheck' 20 prop_assoc_builder_str
  log "Check JAssoc append `~>`"
  quickCheck' 20 prop_assoc_append
  log "Check get field `obj .? 'foo'`"
  quickCheck' 20 prop_get_jobject_field
  log "Assert maybe to either convertion"
  assert assert_maybe_msg

newtype MyRecord = MyRecord { foo :: String, bar :: Int}
derive instance genericMyRecord :: Generic MyRecord

data User = Anonymous
          | Guest String
          | Registered { name :: String
                       , age :: Int
                       , balance :: Number
                       , banned :: Boolean
                       , tweets :: Array String
                       , followers :: Array User
                       }
derive instance genericUser :: Generic User

prop_iso_generic :: GenericValue -> Boolean
prop_iso_generic genericValue =
  Right val.spine == genericDecodeJson' argonautOptions val.signature (genericEncodeJson' argonautOptions val.signature val.spine)
  where val = runGenericValue genericValue

prop_decoded_spine_valid :: GenericValue -> Boolean
prop_decoded_spine_valid genericValue =
  Right true == (isValidSpine val.signature <$> genericDecodeJson' argonautOptions val.signature (genericEncodeJson' argonautOptions val.signature val.spine))
  where val = runGenericValue genericValue

genericsCheck = do
  log "Check that decodeJson' and encodeJson' form an isomorphism"
  quickCheck prop_iso_generic
  log "Check that decodeJson' returns a valid spine"
  quickCheck prop_decoded_spine_valid
  log "Print samples of values encoded with gEncodeJson"
  print $ gEncodeJson 5
  print $ gEncodeJson [1, 2, 3, 5]
  print $ gEncodeJson (Just "foo")
  print $ gEncodeJson (Right "foo" :: Either String String)
  print $ gEncodeJson $ MyRecord { foo: "foo", bar: 2}
  print $ gEncodeJson "foo"
  print $ gEncodeJson Anonymous
  print $ gEncodeJson $ Guest "guest's handle"
  print $ gEncodeJson $ Registered { name: "user1"
                                   , age: 5
                                   , balance: 26.6
                                   , banned: false
                                   , tweets: ["Hello", "What's up"]
                                   , followers: [ Anonymous
                                                , Guest "someGuest"
                                                , Registered { name: "user2"
                                                             , age: 6
                                                             , balance: 32.1
                                                             , banned: false
                                                             , tweets: ["Hi"]
                                                             , followers: []
                                                             }]}


eitherCheck = do
  log "Test EncodeJson/DecodeJson Either instance"
  quickCheck \(x :: Either String String) ->
    case decodeJson (encodeJson x) of
      Right decoded ->
        decoded == x
          <?> ("x = " <> show x <> ", decoded = " <> show decoded)
      Left err ->
        false <?> err

main = do
  eitherCheck
  encodeDecodeCheck
  combinatorsCheck
  genericsCheck
