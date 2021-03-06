{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

-- | This module is a public API implementation

module Main where

import           Control.Arrow            hiding (app)
import           Control.Exception        (catch)
import           Control.Lens
import           Data.Maybe               (fromMaybe)
import           Data.Monoid
import           Data.String.Class        (fromStrictByteString, toString)
import           Data.Text                (Text)
import qualified Data.Text                as T
import           Network.HTTP.Client      hiding (Request, queryString,
                                           requestBody, requestHeaders)
import           Network.HTTP.Types       (status404, status500)
import           Network.Wai
import           Network.Wai.Handler.Warp hiding (Manager)
import qualified Network.Wreq             as W

app :: Manager -> Application
app mgr req respond =
    case pathInfo req of
        ("api":"users":_) -> microservice "http://localhost:8082/"
        ("api":"albooms":_) -> microservice "http://localhost:8083/"
        _ -> respond (responseLBS status404 [] ",,,(o,o),,,\n ';:`-':;' \n   -\"-\"-   \n")
  where
    microservice = microserviceProxy mgr req respond

getReqParams :: Request -> [(Text, Text)]
getReqParams req = map (fromStrictByteString *** fromStrictByteString . fromMaybe "") (queryString req)

microserviceProxy :: Manager -> Request -> (Network.Wai.Response -> IO b) -> Text
                  -> IO b
microserviceProxy mgr req respond basePath = do
    let opts = W.defaults & W.manager .~ Right mgr
                          & W.headers .~ requestHeaders req
                          & W.params .~ getReqParams req
        url = basePath <> T.intercalate "/" (pathInfo req)
    tryProxying opts url `catch` onErr
  where
    tryProxying opts url = do
      r <- case requestMethod req of
             "GET" -> W.getWith opts (toString url)
             "POST" -> requestBody req >>= W.postWith opts (toString url)
      respond (responseLBS (r ^. W.responseStatus) (r ^. W.responseHeaders)
                 (r ^. W.responseBody))
    onErr (StatusCodeException s hdrs _) = respond (responseLBS s hdrs "")
    onErr e = do
      putStrLn ("Internal error: " ++ show e)
      respond (responseLBS status500 [] "Internal server error")

main :: IO ()
main = do
    mgr <- newManager defaultManagerSettings
    run 8081 (app mgr)
