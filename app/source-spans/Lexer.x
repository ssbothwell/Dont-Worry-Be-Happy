{
module Lexer where

import Data.Bits ((.&.), shiftR)
import Data.Char (ord)
import Data.Word (Word8)
}

$digit = 0-9
$alpha = [a-zA-Z]
$alphanum = [a-zA-Z09]

tokens :-

-- Whitespace insensitive
$white+                       ;

-- Comments
"#".*                         ;

-- Syntax

(λ|\\)                        { \pos _ -> TokenExt Lambda pos }
\.                            { \pos _ -> TokenExt Dot pos }
\(                            { \pos _ -> TokenExt OpenParen pos }
\)                            { \pos _ -> TokenExt CloseParen pos }
$alpha [$alpha $digit \_ \-]* { \pos s -> TokenExt (Identifier s) pos }


{
data Token
  = Identifier String
  | Lambda
  | Dot
  | OpenParen
  | CloseParen
  deriving Show

data TokenExt = TokenExt { token :: Token, sourcePos :: AlexSourcePos }
  deriving Show

data AlexSourcePos = AlexSourcePos { line :: !Int , col :: !Int }
  deriving Show

incCol :: Int -> AlexSourcePos -> AlexSourcePos
incCol i (AlexSourcePos l c) = AlexSourcePos l (i + c)

incLine :: Int -> AlexSourcePos -> AlexSourcePos
incLine i (AlexSourcePos l c) = AlexSourcePos (i + l) c

data AlexInput = AlexInput
  { currentPos :: AlexSourcePos
  , prevChar   :: Char
  , pendingBytes :: [Word8]
  -- ^ pending bytes on current char
  , inputString :: String
  -- ^ current input string
  }

-- | Encode a Haskell String to a list of Word8 values, in UTF8 format.
utf8Encode :: Char -> [Word8]
utf8Encode = uncurry (:) . utf8Encode'

utf8Encode' :: Char -> (Word8, [Word8])
utf8Encode' c =
  let (x, xs) = go (ord c)
  in (fromIntegral x, map fromIntegral xs)
 where
  go oc
   | oc <= 0x7f       = ( oc, [])
   | oc <= 0x7ff      = ( 0xc0 + (oc `shiftR` 6), [0x80 + oc .&. 0x3f])
   | oc <= 0xffff     = ( 0xe0 + (oc `shiftR` 12)
                        , [0x80 + ((oc `shiftR` 6) .&. 0x3f), 0x80 + oc .&. 0x3f])
   | otherwise        = ( 0xf0 + (oc `shiftR` 18)
                        , [0x80 + ((oc `shiftR` 12) .&. 0x3f)
                          , 0x80 + ((oc `shiftR` 6) .&. 0x3f)
                          , 0x80 + oc .&. 0x3f
                          ])

alexStartPos :: AlexSourcePos
alexStartPos = AlexSourcePos 1 1

alexMove :: AlexSourcePos -> Char -> AlexSourcePos
alexMove (AlexSourcePos l c) '\t' = AlexSourcePos l (c+alex_tab_size-((c-1) `mod` alex_tab_size))
alexMove (AlexSourcePos l _) '\n' = AlexSourcePos (l+1) 1
alexMove (AlexSourcePos l c) _    = AlexSourcePos l (c+1)

alexGetByte :: AlexInput -> Maybe (Word8, AlexInput)
alexGetByte (AlexInput p c (b:bs) s) = Just (b, AlexInput p c bs s)
alexGetByte (AlexInput _ _ [] []) = Nothing
alexGetByte (AlexInput p _ [] (c:s))  =
  let p' = alexMove p c
  in case utf8Encode' c of
    (b, bs) -> p' `seq` Just (b, AlexInput p' c bs s)

lexer :: String -> [TokenExt]
lexer str = go (AlexInput alexStartPos '\n' [] str)
  where go inp@(AlexInput pos _ _ str) =
          case alexScan inp 0 of
            AlexEOF -> []
            AlexError (AlexInput (AlexSourcePos line column) _ _ _) -> error $ "lexical error at " ++ (show line) ++ " line, " ++ (show column) ++ " column"
            AlexSkip  inp' len     -> go inp'
            AlexToken inp' len act -> act pos (take len str) : go inp'
}
