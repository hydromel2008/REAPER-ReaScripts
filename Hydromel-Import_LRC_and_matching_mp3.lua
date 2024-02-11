------------------------------------------------------------------------
-- @version 1.00
-- @author Hydromel
-- @description Inter/Convert SRT file into text items and matches with
-- @dependencies
--    REAPER v7.08
--    SWS v2.13.2.0
--    Reapack v1.2.4.3
-- 
-- description: This script will import LRC file and matching mp3 file into Reaper.
--              It will create a new track for the lyrics and a new track for the mp3 file.
--              The result will be in a format compatible with X-Raym's "Script: X-Raym_Convert first selected track items notes for scrolling web browser interface.lua" script.
--              which is useful for creating scrolling lyrics for live performances.
------------------------------------------------------------------------

for key in pairs(reaper) do _G[key] = reaper[key] end -- makes reaper API functions available as if they were local functions
local scr = 'Convert LRC file into dummy items'
----------------------------------------------------
function msg(s)
  if not s then return end
  reaper.ShowConsoleMsg(s .. '\n')
end

function file_exists(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

function unselectAllTracks()
  reaper.Main_OnCommand(40297, 0) -- Command ID for "Unselect all tracks"
end

function selectTrackOnly(track)
  unselectAllTracks()
  reaper.SetTrackSelected(track, true)
end

function setCurrentTrack(track)
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(40914, 0) -- Command ID for "Set last touched track as last selected track"
end

-- Function to set last touched track as selected
function setTrackAsLastTouched(track)
  -- Unselect all tracks
  unselectAllTracks()
  -- Set the last touched track as selected
  reaper.SetTrackSelected(track, true)
  -- Set the last touched track as the last selected track
  reaper.Main_OnCommand(40914, 0) -- Command ID for "Set last touched track as last selected track"
end

-- Example function to convert LRC time format to seconds
function lrcTimeToSeconds(timeStr)
  local minutes, seconds = timeStr:match("(%d+):(%d+%.%d+)")
  return tonumber(minutes) * 60 + tonumber(seconds)
end

-- Function to create empty items at lyric timestamps on the "Lyrics" track
function createLyricItems(lyrics, track, position)
  local defaultLength = 2
  for i, lyric in ipairs(lyrics) do
    -- if it's first time, add a media item to the start of the project
    if i == 1 then
      local text = " "
      local startTime = position
      local endTime = startTime + defaultLength
      local itemLength = endTime - startTime
      local item = reaper.AddMediaItemToTrack(track)
      reaper.SetMediaItemPosition(item, startTime, false)
      reaper.SetMediaItemLength(item, itemLength, false)
      local take = reaper.AddTakeToMediaItem(item)
      reaper.ULT_SetMediaItemNote(item, text)
      reaper.UpdateItemInProject(item)
    end
    local startTime = lrcTimeToSeconds(lyric.time) + position -- Adjust start time by cursor position
    local endTime
    -- Process lyrics
    if i < #lyrics then
      endTime = lrcTimeToSeconds(lyrics[i + 1].time) + position
    else
      endTime = startTime + defaultLength -- Default length for the last item, adjust as needed
    end
    local itemLength = endTime - startTime
    local item = reaper.AddMediaItemToTrack(track)
    reaper.SetMediaItemPosition(item, startTime, false)
    reaper.SetMediaItemLength(item, itemLength, false)

    -- Add the lyric text as item note (SWS extension required)
    local take = reaper.AddTakeToMediaItem(item)
    if lyric.text == "" then lyric.text = " " end

    reaper.ULT_SetMediaItemNote(item, lyric.text)
    reaper.UpdateItemInProject(item)
  end
end

--
-- Function to read LRC file and extract all timestamps and texts into a table
--
function parseLRC(content)
  local lyrics = {}
  for line in content:gmatch('[^\r\n]+') do
    local time, text = line:match("%[(%d+:%d+%.%d+)%]%s*(.*)")
    if time and text then
      table.insert(lyrics, { time = time, text = text })
    end
  end
  return lyrics
end

function findOrCreateTrackByName(trackName)
  local trackCount = reaper.CountTracks(0)
  for i = 0, trackCount - 1 do
    local track = reaper.GetTrack(0, i)
    local _, currentTrackName = reaper.GetTrackName(track, "")
    if currentTrackName == trackName then
      return track
    end
  end
  -- Track not found, create it
  reaper.InsertTrackAtIndex(trackCount, true)
  local newTrack = reaper.GetTrack(0, trackCount) -- Get the newly created track
  reaper.GetSetMediaTrackInfo_String(newTrack, "P_NAME", trackName, true)
  return newTrack
end

function insertMP3ToTrack(track, filePath)
  -- Unselect all items
  reaper.Main_OnCommand(40289, 0) -- Command ID for "Unselect all items"
  -- Insert the MP3 file into the specified track
  setCurrentTrack(track)
  reaper.InsertMedia(filePath, 0)
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, reaper.PCM_Source_CreateFromFile(filePath))
  reaper.UpdateArrange()          -- Update the arrangement view
  reaper.Main_OnCommand(40047, 0) -- Peform action: "Build any missing peak files"

  -- Get the duration of the item
  local commandID = "_SWS_REGIONSFROMITEMS" -- This is a placeholder; you need to replace it with the actual ID
  local resolvedCommandID = reaper.NamedCommandLookup(commandID)

  if resolvedCommandID ~= 0 then
    reaper.Main_OnCommand(resolvedCommandID, 0) -- 0 is for normal execution
  else
    reaper.ShowMessageBox("SWS extension is not installed or the command ID is incorrect.", "Error", 0)
  end
  -- msg("Duration of MP3 file: " .. itemLength  .. " seconds")

  return track, item, take
end

----------------------------------------------------
function main(fp)
  if not file_exists(fp) then return end

  local cursorPosition = reaper.GetCursorPosition() -- Get the current cursor position

  local track = findOrCreateTrackByName('LYRICS')
  local mp3Track = findOrCreateTrackByName('SONGS')

  selectTrackOnly(track)

  -- check file
  local f = io.open(fp, 'r')

  -- Find matching mp3 file
  local mp3FilePath = fp:gsub(".lrc$", ".mp3")
  local mp3found = file_exists(mp3FilePath)

  if mp3found then
    local mp3Track = findOrCreateTrackByName('SONGS')
    selectTrackOnly(mp3Track)
    insertMP3ToTrack(mp3Track, mp3FilePath)
  end

  -- extract content
  content = f:read('a')
  -- close handle

  -- Load lyrics
  local lyrics = parseLRC(content)
  selectTrackOnly(track)
  createLyricItems(lyrics, track, cursorPosition)
end

local track = reaper.GetSelectedTrack(0, 0)

retval, fn = GetUserFileNameForRead('', scr, '.lrc')

if retval then
  reaper.ClearConsole()
  reaper.Undo_BeginBlock()
  main(fn)
  reaper.Undo_EndBlock(scr, 1)
end
