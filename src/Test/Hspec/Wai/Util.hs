{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE CPP #-}
module Test.Hspec.Wai.Util where

import           Control.Monad
import           Data.Maybe
import           Data.List
import           Data.Word
import           Data.Char hiding (ord)
import qualified Data.Char as Char
import           Data.ByteString (ByteString)
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as LB
import           Data.ByteString.Lazy.Builder (Builder)
import qualified Data.ByteString.Lazy.Builder as Builder
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.CaseInsensitive as CI
import           Network.HTTP.Types

#if !MIN_VERSION_base(4,11,0)
import           Data.Monoid
#endif

formatHeader :: Header -> String
formatHeader header@(name, value) = "  " ++ fromMaybe (show header) (safeToString $ B8.concat [CI.original name, ": ", value])

safeToString :: ByteString -> Maybe String
safeToString bs = do
  str <- either (const Nothing) (Just . T.unpack) (T.decodeUtf8' bs)
  let isSafe = not $ case str of
        [] -> True
        _  -> isSpace (last str) || any (not . isPrint) str
  guard isSafe >> return str

-- for compatibility with older versions of `bytestring`
toStrict :: LB.ByteString -> ByteString
toStrict = mconcat . LB.toChunks

formUrlEncodeQuery :: [(String, String)] -> LB.ByteString
formUrlEncodeQuery = Builder.toLazyByteString . mconcat . intersperse amp . map encodePair
  where
    equals = Builder.word8 (ord '=')
    amp = Builder.word8 (ord '&')
    percent = Builder.word8 (ord '%')
    plus = Builder.word8 (ord '+')

    encodePair :: (String, String) -> Builder
    encodePair (key, value) = encode key <> equals <> encode value

    encode :: String -> Builder
    encode = escape . T.encodeUtf8 . T.pack . newlineNormalize

    newlineNormalize :: String -> String
    newlineNormalize input = case input of
      [] -> []
      '\n' : xs -> '\r' : '\n': newlineNormalize xs
      x : xs -> x : newlineNormalize xs

    escape :: ByteString -> Builder
    escape = mconcat . map f . B.unpack
      where
        f :: Word8 -> Builder
        f c
          | p c = Builder.word8 c
          | c == ord ' ' = plus
          | otherwise = percentEncode c

        p :: Word8 -> Bool
        p c =
             ord 'a' <= c && c <= ord 'z'
          || c == ord '_'
          || c == ord '*'
          || c == ord '-'
          || c == ord '.'
          || ord '0' <= c && c <= ord '9'
          || ord 'A' <= c && c <= ord 'Z'

    ord :: Char -> Word8
    ord = fromIntegral . Char.ord

    percentEncode :: Word8 -> Builder
    percentEncode n = percent <> hex hi <> hex lo
      where
        (hi, lo) = n `divMod` 16

    hex :: Word8 -> Builder
    hex n = Builder.word8 (offset + n)
      where
        offset
          | n < 10    = 48
          | otherwise = 55
