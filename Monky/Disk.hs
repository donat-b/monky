{-
    Copyright 2015 Markus Ongyerth, Stephan Guenther

    This file is part of Monky.

    Monky is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Monky is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with Monky.  If not, see <http://www.gnu.org/licenses/>.
-}
{-|
Module      : Monky.Disk
Description : Allows access to information about a btrfs pool
Maintainer  : moepi
Stability   : experimental
Portability : Linux

This module allows for some support for btrfs devices.
This may be renamed in the future when a general block-device module appears.
-}
module Monky.Disk (DiskHandle, getDiskReadWrite, getDiskFree, getDiskHandle)
where

import Data.Time.Clock.POSIX
import Data.IORef

-- |The handle exported by this module
data DiskHandle = BTRFSH String Int Int (IORef Int) (IORef Int) (IORef POSIXTime) | Empty

path :: String
path = "/proc/diskstats"

basePath :: String
basePath = "/sys/block/"

fsBasePath :: String
fsBasePath = "/sys/fs/btrfs/"

fsUUID :: String
fsUUID = "cb592ffc-c82e-4e14-b513-45358e7d4b93"

sectorSize :: Int
sectorSize = 512

-- |Get the read write rates from the disk (in bytes/s)
getDiskReadWrite :: DiskHandle -> IO (Int, Int)
getDiskReadWrite Empty = return (0, 0)
getDiskReadWrite (BTRFSH _ _ _ readref writeref timeref) = do
  content <- readFile path
  time <- getPOSIXTime
  let values = map read . drop 1 . head . filter (\l -> head l == "dm-0") . map (drop 2 . words) $ lines content :: [Int]
  let nread = (values !! 2) * sectorSize
  let write = (values !! 6) * sectorSize
  oread <- readIORef readref
  owrite <- readIORef writeref
  otime <- readIORef timeref
  let cread = nread - oread
  let cwrite = write - owrite
  let ctime = time - otime
  writeIORef readref nread
  writeIORef writeref write
  writeIORef timeref time
  return (div cread (round ctime), div cwrite (round ctime))

-- |Get the space left on the disk
getDiskFree :: DiskHandle -> IO Int
getDiskFree Empty = return 0
getDiskFree (BTRFSH _ _ size _ _ _) = do
  dused <- readFile (fsBasePath ++ fsUUID ++ "/allocation/data/bytes_used")
  mused <- readFile (fsBasePath ++ fsUUID ++ "/allocation/metadata/bytes_used")
  sused <- readFile (fsBasePath ++ fsUUID ++ "/allocation/system/bytes_used")
  let dfree = size - (read dused :: Int) - (read mused :: Int) - (read sused :: Int)
  return $div dfree 1000000000

-- |Get the disk handle
getDiskHandle :: String -> Int -> IO DiskHandle
getDiskHandle "" 0 = return Empty
getDiskHandle dev part = do
  content <- readFile (basePath ++ dev ++ "/" ++ dev ++ show part ++ "/size")
  let size = (read content :: Int) * sectorSize
  readref <- newIORef (0 :: Int)
  writeref <- newIORef (0 :: Int)
  timeref <- newIORef (0 :: POSIXTime)
  return $BTRFSH dev part size readref writeref timeref