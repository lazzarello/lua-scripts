--[[

    stipplegen.lua - Render a portrait with stipplegen

    Portions are lifted from gimp.lua and thus are

    Copyright (C) 2016 Bill Ferguson <wpferguson@gmail.com>.

    gimp.lua has portions lifted from hugin.lua and thus are

    Copyright (c) 2014  Wolfgang Goetz
    Copyright (c) 2015  Christian Kanzian
    Copyright (c) 2015  Tobias Jakobs


    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
    stipplegen - export an image and open with stipplegen 

    Selected images are opened in StippleGen to render as a half-toned image. This program is CPU heavy. Probably a bad idea to export multiple.

    ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT
    * StippleGen

    USAGE
    * require this script from your main lua file
    * select an image to render
    * in the export dialog select "Render with Stipplegen" and select the format and bit depth for the
      exported image
    * Press "export"

    BUGS, COMMENTS, SUGGESTIONS
    * Send to Bill Ferguson, wpferguson@gmail.com

    CHANGES
    * 20160508 - edit to open stipplegen with processing-java
    * 20160823 - os.rename doesn't work across filesystems.  Added fileCopy and fileMove functions to move the file
                 from the temporary location to the collection location irregardless of what filesystem it is on.  If an
                 issue is encountered, a message is printed back to the UI so the user isn't left wondering what happened.
]]

local dt = require "darktable"
local df = require "lib/dtutils.file"
require "official/yield"
local gettext = dt.gettext

dt.configuration.check_version(...,{3,0,0},{4,0,0},{5,0,0})

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("stipplegen",dt.configuration.config_dir.."/lua/locale/")

local function split_filepath(str)
  local result = {}
  -- Thank you Tobias Jakobs for the awesome regular expression, which I tweaked a little
  result["path"], result["filename"], result["basename"], result["filetype"] = string.match(str, "(.-)(([^\\/]-)%.?([^%.\\/]*))$")
  return result
end

local function get_path(str)
  local parts = split_filepath(str)
  return parts["path"]
end

local function get_filename(str)
  local parts = split_filepath(str)
  return parts["filename"]
end

local function get_basename(str)
  local parts = split_filepath(str)
  return parts["basename"]
end

local function get_filetype(str)
  local parts = split_filepath(str)
  return parts["filetype"]
end

local function _(msgid)
    return gettext.dgettext("stipplegen", msgid)
end

-- Thanks Tobias Jakobs for the idea and the correction
function checkIfFileExists(filepath)
  local file = io.open(filepath,"r")
  local ret
  if file ~= nil then
    io.close(file)
    dt.print_error("true checkIfFileExists: "..filepath)
    ret = true
  else
    dt.print_error(filepath.." not found")
    ret = false
  end
  return ret
end

local function filename_increment(filepath)

  -- break up the filepath into parts
  local path = get_path(filepath)
  local basename = get_basename(filepath)
  local filetype = get_filetype(filepath)

  -- check to see if we've incremented before
  local increment = string.match(basename, "_(%d-)$")

  if increment then
    -- we do 2 digit increments so make sure we didn't grab part of the filename
    if string.len(increment) > 2 then
      -- we got the filename so set the increment to 01
      increment = "01"
    else
      increment = string.format("%02d", tonumber(increment) + 1)
      basename = string.gsub(basename, "_(%d-)$", "")
    end
  else
    increment = "01"
  end
  local incremented_filepath = path .. basename .. "_" .. increment .. "." .. filetype

  dt.print_error("original file was " .. filepath)
  dt.print_error("incremented file is " .. incremented_filepath)

  return incremented_filepath
end

local function groupIfNotMember(img, new_img)
  local image_table = img:get_group_members()
  local is_member = false
  for _,image in ipairs(image_table) do
    dt.print_error(image.filename .. " is a member")
    if image.filename == new_img.filename then
      is_member = true
      dt.print_error("Already in group")
    end
  end
  if not is_member then
    dt.print_error("group leader is "..img.group_leader.filename)
    new_img:group_with(img.group_leader)
    dt.print_error("Added to group")
  end
end

local function sanitize_filename(filepath)
  local path = get_path(filepath)
  local basename = get_basename(filepath)
  local filetype = get_filetype(filepath)

  local sanitized = string.gsub(basename, " ", "\\ ")

  return path .. sanitized .. "." .. filetype
end

local function show_status(storage, image, format, filename,
  number, total, high_quality, extra_data)
    dt.print(string.format(_("Export Image %i/%i"), number, total))
end

local function fileCopy(fromFile, toFile)
  local result = nil
  -- if cp exists, use it
  if df.check_if_bin_exists("cp") then
    result = os.execute("cp '" .. fromFile .. "' '" .. toFile .. "'")
  end
  -- if cp was not present, or if cp failed, then a pure lua solution
  if not result then
    local fileIn, err = io.open(fromFile, 'rb')
    if fileIn then
      local fileOut, errr = io.open(toFile, 'w')
      if fileOut then
        local content = fileIn:read(4096)
        while content do
          fileOut:write(content)
          content = fileIn:read(4096)
        end
        result = true
        fileIn:close()
        fileOut:close()
      else
        dt.print_error("fileCopy Error: " .. errr)
      end
    else
      dt.print_error("fileCopy Error: " .. err)
    end
  end
  return result
end

local function fileMove(fromFile, toFile)
  local success = os.rename(fromFile, toFile)
  if not success then
    -- an error occurred, so let's try using the operating system function
    if df.check_if_bin_exists("mv") then
      success = os.execute("mv '" .. fromFile .. "' '" .. toFile .. "'")
    end
    -- if the mv didn't exist or succeed, then...
    if not success then
      -- pure lua solution
      success = fileCopy(fromFile, toFile)
      if success then
        os.remove(fromFile)
      else
        dt.print_error("fileMove Error: Unable to move " .. fromFile .. " to " .. toFile .. ".  Leaving " .. fromFile .. " in place.")
        dt.print(string.format(_("Unable to move edited file into collection. Leaving it as %s"), fromFile))
      end
    end
  end
  return success  -- nil on error, some value if success
end

local function stipple_render(storage, image_table, extra_data) --finalize
  if not df.check_if_bin_exists("processing-java") then
    dt.print_error(_("processing-java not found"))
    return
  end

  -- list of exported images
  local img_list

  -- absolute path to StippleGen processing sketch
  local sketch_path = "/home/ordi/src/stipplegen/StippleGen"
   -- reset and create image list
  img_list = ""

  for _,exp_img in pairs(image_table) do
    exp_img = sanitize_filename(exp_img)
    img_list = img_list ..exp_img.. " "
  end

  dt.print(_("Launching StippleGen..."))

  local stippleStartCommand
  stippleStartCommand = "processing-java --sketch="..sketch_path.." --run "..img_list

  dt.print_error(stippleStartCommand)

  dt.control.execute( stippleStartCommand)

  -- for each of the image, exported image pairs
  --   move the exported image into the directory with the original
  --   then import the image into the database which will group it with the original
  --   and then copy over any tags other than darktable tags

  for image,exported_image in pairs(image_table) do

    local myimage_name = image.path .. "/" .. get_filename(exported_image)

    --[[
    while checkIfFileExists(myimage_name) do
      myimage_name = filename_increment(myimage_name)
      -- limit to 99 more exports of the original export
      if string.match(get_basename(myimage_name), "_(d-)$") == "99" then
        break
      end
    end

    dt.print_error("moving " .. exported_image .. " to " .. myimage_name)
    local result = fileMove(exported_image, myimage_name)
    if result then
      dt.print_error("importing file")
      local myimage = dt.database.import(myimage_name)

      groupIfNotMember(image, myimage)

      for _,tag in pairs(dt.tags.get_tags(image)) do
        if not (string.sub(tag.name,1,9) == "darktable") then
          dt.print_error("attaching tag")
          dt.tags.attach(tag,myimage)
        end
      end
    end
    ]]
  end

end

-- Register
dt.register_storage("module_gimp", _("Open with Stipplegen"), show_status, stipple_render)

--
