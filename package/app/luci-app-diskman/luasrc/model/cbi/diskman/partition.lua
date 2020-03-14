--[[
LuCI - Lua Configuration Interface
Copyright 2019 lisaac <https://github.com/lisaac/luci-app-diskman>
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
  http://www.apache.org/licenses/LICENSE-2.0
$Id$
]]--

require "luci.util"
require("luci.tools.webadmin")
local dm = require "luci.model.diskman"
local dev = arg[1]

if not dev then
  luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
elseif not nixio.fs.access("/dev/"..dev) then
  luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
end

m = SimpleForm("partition", translate("Partition Management"), translate("Partition Disk over LuCI."))
m.template = "diskman/cbi/xsimpleform"
m.redirect = luci.dispatcher.build_url("admin/system/diskman")
m:append(Template("diskman/partition_info"))
-- disable submit and reset button
m.submit = false
m.reset = false

local disk_info = dm.get_disk_info(dev, true)
local format_cmd = dm.get_format_cmd()

s = m:section(Table, {disk_info}, translate("Device Info"))
-- s:option(DummyValue, "key")
-- s:option(DummyValue, "value")
s:option(DummyValue, "path", translate("Path"))
s:option(DummyValue, "model", translate("Model"))
s:option(DummyValue, "sn", translate("Serial Number"))
s:option(DummyValue, "size_formated", translate("Size"))
s:option(DummyValue, "sec_size", translate("Sector Size "))
local dv_p_table = s:option(ListValue, "p_table", translate("Partition Table"))
dv_p_table.render = function(self, section, scope)
  if not disk_info.p_table:match("Raid") and (#disk_info.partitions == 0 or (#disk_info.partitions == 1 and disk_info.partitions[1].number == -1)) then
    self:value(disk_info.p_table, disk_info.p_table)
    self:value("GPT", "GPT")
    self:value("MBR", "MBR")
    self.default = disk_info.p_table
    ListValue.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    DummyValue.render(self, section, scope)
  end
end
if disk_info.type:match("md") then
  s:option(DummyValue, "level", translate("Level"))
  s:option(DummyValue, "members_str", translate("Members"))
else
  s:option(DummyValue, "temp", translate("Temp"))
  s:option(DummyValue, "sata_ver", translate("SATA Version"))
  s:option(DummyValue, "rota_rate", translate("Rotation Rate"))
end
s:option(DummyValue, "status", translate("Status"))
local btn_health = s:option(Button, "health", translate("Health"))
btn_health.render = function(self, section, scope)
  if disk_info.health then
    self.inputtitle = disk_info.health
    if disk_info.health == "PASSED" then
      self.inputstyle = "add"
    else
      self.inputstyle = "remove"
    end
    Button.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    DummyValue.render(self, section, scope)
  end
end

local btn_eject = s:option(Button, "_eject")
btn_eject.template = "diskman/cbi/disabled_button"
btn_eject.inputstyle = "remove"
btn_eject.render = function(self, section, scope)
  for i, p in ipairs(disk_info.partitions) do
    if p.mount_point ~= "-" then
      self.view_disabled = true
      break
    end
  end
  if disk_info.p_table:match("Raid") then
    self.view_disabled = true
  end
  if disk_info.type:match("md") then
    btn_eject.inputtitle = translate("Remove")
  else
    btn_eject.inputtitle = translate("Eject")
  end
  Button.render(self, section, scope)
end
btn_eject.forcewrite = true
btn_eject.write = function(self, section, value)
  for i, p in ipairs(disk_info.partitions) do
    if p.mount_point ~= "-" then
      m.errmessage = p.name .. "is in use! please unmount it first!"
      return
    end
  end
  if disk_info.type:match("md") then
    luci.util.exec(dm.command.mdadm .. " --stop /dev/" .. dev)
    luci.util.exec(dm.command.mdadm .. " --remove /dev/" .. dev)
    for _, disk in ipairs(disk_info.members) do
      luci.util.exec(dm.command.mdadm .. " --zero-superblock " .. disk)
    end
    dm.gen_mdadm_config()
  else
    luci.util.exec("echo 1 > /sys/block/" .. dev .. "/device/delete")
  end
  luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
end
-- eject: echo 1 > /sys/block/(device)/device/delete
-- rescan: echo '- - -' | tee /sys/class/scsi_host/host*/scan > /dev/null


-- partitions info
if not disk_info.p_table:match("Raid") then
  s_partition_table = m:section(Table, disk_info.partitions, translate("Partitions Info"), translate("Default 2048 sector alignment, support +size{b,k,m,g,t} in End Sector"))

  -- s_partition_table:option(DummyValue, "number", translate("Number"))
  s_partition_table:option(DummyValue, "name", translate("Name"))
  local val_sec_start = s_partition_table:option(Value, "sec_start", translate("Start Sector"))
  val_sec_start.render = function(self, section, scope)
    -- could create new partition
    if disk_info.partitions[section].number == -1 and disk_info.partitions[section].size > 1 * 1024 * 1024 then
      self.template = "cbi/value"
      Value.render(self, section, scope)
    else
      self.template = "cbi/dvalue"
      DummyValue.render(self, section, scope)
    end
  end
  local val_sec_end = s_partition_table:option(Value, "sec_end", translate("End Sector"))
  val_sec_end.render = function(self, section, scope)
    -- could create new partition
    if disk_info.partitions[section].number == -1 and disk_info.partitions[section].size > 1 * 1024 * 1024 then
      self.template = "cbi/value"
      Value.render(self, section, scope)
    else
      self.template = "cbi/dvalue"
      DummyValue.render(self, section, scope)
    end
  end
  val_sec_start.forcewrite = true
  val_sec_start.write = function(self, section, value)
    disk_info.partitions[section]._sec_start = value
  end
  val_sec_end.forcewrite = true
  val_sec_end.write = function(self, section, value)
    disk_info.partitions[section]._sec_end = value
  end
  s_partition_table:option(DummyValue, "size_formated", translate("Size"))
  if disk_info.p_table == "MBR" then
    s_partition_table:option(DummyValue, "type", translate("Type"))
  end
  s_partition_table:option(DummyValue, "useage", translate("Useage"))
  s_partition_table:option(DummyValue, "mount_point", translate("Mount Point"))
  local val_fs = s_partition_table:option(Value, "fs", translate("File System"))
  val_fs.forcewrite = true
  val_fs.write = function(self, section, value)
    disk_info.partitions[section]._fs = value
  end
  val_fs.render = function(self, section, scope)
    -- use listvalue when partition not mounted
    if disk_info.partitions[section].mount_point == "-" and disk_info.partitions[section].number ~= -1 and disk_info.partitions[section].type ~= "extended" then
      self.template = "cbi/value"
      self:reset_values()
      self.keylist = {}
      self.vallist = {}
      for k, v in pairs(format_cmd) do
        self:value(k,k)
      end
      -- self.default = disk_info.partitions[section].fs
    else
      self:reset_values()
      self.keylist = {}
      self.vallist = {}
      self.template = "cbi/dvalue"
    end
    DummyValue.render(self, section, scope)
  end
  btn_format = s_partition_table:option(Button, "_format")
  btn_format.render = function(self, section, scope)
    if disk_info.partitions[section].mount_point == "-" and disk_info.partitions[section].number ~= -1 and disk_info.partitions[section].type ~= "extended" then
      self.inputtitle = translate("Format")
      self.template = "diskman/cbi/disabled_button"
      self.view_disabled = false
      self.inputstyle = "reset"
      for k, v in pairs(format_cmd) do
        self:depends("val_fs", "k")
      end
    -- elseif disk_info.partitions[section].mount_point ~= "-" and disk_info.partitions[section].number ~= -1 then
    --   self.inputtitle = "Format"
    --   self.template = "diskman/cbi/disabled_button"
    --   self.view_disabled = true
    --   self.inputstyle = "reset"
    else
      self.inputtitle = ""
      self.template = "cbi/dvalue"
    end
    Button.render(self, section, scope)
  end
  btn_format.forcewrite = true
  btn_format.write = function(self, section, value)
    local partition_name = "/dev/".. disk_info.partitions[section].name
    if not nixio.fs.access(partition_name) then
      m.errmessage = "Partition NOT found!"
      return
    end
    local fs = disk_info.partitions[section]._fs
    if not format_cmd[fs] then
      m.errmessage = "Filesystem NOT support!"
      return
    end
    local cmd = format_cmd[fs].cmd .. " " .. format_cmd[fs].option .. " " .. partition_name
    -- luci.util.perror(cmd)
    local res = luci.sys.exec(cmd)
    luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman/partition/" .. dev))
  end

  local btn_action = s_partition_table:option(Button, "_action")
  btn_action.forcewrite = true
  btn_action.template = "diskman/cbi/disabled_button"
  btn_action.render = function(self, section, scope)
    -- if partition is mounted or the size < 1mb, then disable the add action
    if disk_info.partitions[section].mount_point ~= "-" or (disk_info.partitions[section].type ~= "extended" and disk_info.partitions[section].number == -1 and disk_info.partitions[section].size <= 1 * 1024 * 1024) then
      self.view_disabled = true
      -- self.inputtitle = ""
      -- self.template = "cbi/dvalue"
    elseif disk_info.partitions[section].type == "extended" and next(disk_info.partitions[section]["logicals"]) ~= nil then
      self.view_disabled = true
    else
      -- self.template = "diskman/cbi/disabled_button"
      self.view_disabled = false
    end
    if disk_info.partitions[section].number ~= -1 then
      self.inputtitle = translate("Remove")
      self.inputstyle = "remove"
    else
      self.inputtitle = translate("New")
      self.inputstyle = "add"
    end
    Button.render(self, section, scope)
  end
  btn_action.write = function(self, section, value)
    -- luci.util.perror(value)
    if value == translate("New") then
      local start_sec = disk_info.partitions[section]._sec_start and tonumber(disk_info.partitions[section]._sec_start) or tonumber(disk_info.partitions[section].sec_start)
      local end_sec = disk_info.partitions[section]._sec_end

      if start_sec then
        -- for sector alignment
        local align = tonumber(disk_info.phy_sec) / tonumber(disk_info.logic_sec)
        align = (align < 2048) and 2048
        if start_sec < 2048 then
          start_sec = "2048" .. "s"
        elseif math.fmod( start_sec, align ) ~= 0 then
          start_sec = tostring(start_sec + align - math.fmod( start_sec, align )) .. "s"
        else
          start_sec = start_sec .. "s"
        end
      else
        m.errmessage = "Invalid Start Sector!"
        return
      end
      -- support +size format for End sector
      local end_size, end_unit = end_sec:match("^+(%d-)([bkmgtsBKMGTS])$")
      if tonumber(end_size) and end_unit then
        local unit ={
          B=1,
          S=512,
          K=1024,
          M=1048576,
          G=1073741824,
          T=1099511627776
        }
        end_unit = end_unit:upper()
        end_sec = tostring(tonumber(end_size) * unit[end_unit] / unit["S"] + tonumber(start_sec:sub(1,-2)) - 1 ) .. "s"
      elseif tonumber(end_sec) then
        end_sec = end_sec .. "s"
      else
        m.errmessage = "Invalid End Sector!"
        return
      end
      local part_type = "primary"
      -- create partition table if no partition table
      if disk_info.p_table == "UNKNOWN" then
        local cmd = dm.command.parted .. " -s /dev/" .. dev .. " mktable gpt"
      elseif disk_info.p_table == "MBR" and disk_info["extended_partition_index"] then
        if tonumber(disk_info.partitions[disk_info["extended_partition_index"]].sec_start) <= tonumber(start_sec:sub(1,-2)) and tonumber(disk_info.partitions[disk_info["extended_partition_index"]].sec_end) >= tonumber(end_sec:sub(1,-2)) then
          part_type = "logical"
          if tonumber(start_sec:sub(1,-2)) - tonumber(disk_info.partitions[section].sec_start) < 2048 then
            start_sec = tonumber(start_sec:sub(1,-2)) + 2048
            start_sec = start_sec .."s"
          end
        end
      end

      -- partiton
      local cmd = dm.command.parted .. " -s -a optimal /dev/" .. dev .. " mkpart " .. part_type .." " .. start_sec .. " " .. end_sec
      local res = luci.util.exec(cmd)
      if res:match("Error.+") then
        m.errmessage = res
      else
        luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman/partition/" .. dev))
      end
    elseif value == translate("Remove") then
      -- remove partition
      local number = tostring(disk_info.partitions[section].number)
      if (not number) or (number == "") then
        m.errmessage = "Partition not exists!"
        return
      end
      local cmd = dm.command.parted .. " -s /dev/" .. dev .. " rm " .. number
      local res = luci.util.exec(cmd)
      if res:match("Error.+") then
        m.errmessage = res
      else
        luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman/partition/" .. dev))
      end
    end
  end
end

return m