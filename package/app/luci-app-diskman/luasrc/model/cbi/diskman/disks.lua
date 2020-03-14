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

-- Use (non-UCI) SimpleForm since we have no related config file
m = SimpleForm("diskman", translate("DiskMan"), translate("Manage Disks over LuCI."))
m.template = "diskman/cbi/xsimpleform"
-- m:append(Template("diskman/disk_info"))
-- disable submit and reset button
m.submit = false
m.reset = false
-- rescan disks
rescan = m:section(SimpleSection)
rescan_button = rescan:option(Button, "_rescan")
rescan_button.inputtitle= translate("Rescan Disks")
rescan_button.template = "diskman/cbi/inlinebutton"
rescan_button.inputstyle = "add"
rescan_button.forcewrite = true
rescan_button.write = function(self, section, value)
  luci.util.exec("echo '- - -' | tee /sys/class/scsi_host/host*/scan > /dev/null")
  if dm.command.mdadm then
    luci.util.exec(dm.command.mdadm .. " --assemble --scan")
  end
  luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
end

-- disks
local disks = dm.list_devices()
d = m:section(Table, disks, translate("Disks"))
d.config = "disk"
-- option(type, id(key of table), text)
d:option(DummyValue, "path", translate("Path"))
d:option(DummyValue, "model", translate("Model"))
d:option(DummyValue, "sn", translate("Serial Number"))
d:option(DummyValue, "size_formated", translate("Size"))
d:option(DummyValue, "temp", translate("Temp"))
-- d:option(DummyValue, "sec_size", translate("Sector Size "))
d:option(DummyValue, "p_table", translate("Partition Table"))
d:option(DummyValue, "sata_ver", translate("SATA Version"))
-- d:option(DummyValue, "rota_rate", translate("Rotation Rate"))
d:option(DummyValue, "health", translate("Health"))
d:option(DummyValue, "status", translate("Status"))

d.extedit = luci.dispatcher.build_url("admin/system/diskman/partition/%s")

-- raid devices
if dm.command.mdadm then
  local raid_devices = dm.list_raid_devices()
  -- raid_devices = diskmanager.getRAIDdevices()
  if next(raid_devices) ~= nil then
    local r = m:section(Table, raid_devices, translate("RAID Devices"))
    r.config = "_raid"
    r:option(DummyValue, "path", translate("Path"))
    r:option(DummyValue, "level", translate("RAID mode"))
    r:option(DummyValue, "size_formated", translate("Size"))
    r:option(DummyValue, "p_table", translate("Partition Table"))
    r:option(DummyValue, "status", translate("Status"))
    r:option(DummyValue, "members_str", translate("Members"))
    r:option(DummyValue, "active", translate("Active"))
    -- local redit = r:option(Button, "rpartition")
    -- redit.inputstyle = "edit"
    -- redit.inputtitle = "Edit"
    -- redit.write = function(self, section)
    --   local url = luci.dispatcher.build_url("admin/system/diskman/partition")
    --   url = url .. "/" .. raid_devices[section].path:match("/dev/(.+)")
    --   luci.http.redirect(url)
    -- end
    r.extedit  = luci.dispatcher.build_url("admin/system/diskman/partition/%s")
  end

end

--tabs
tab_section = m:section(SimpleSection)
tab_section.tabs = {
  mount_point = translate("Mount Point")
}
tab_section.default_tab = "mount_point"
tab_section.template="diskman/disk_info_tab"

-- raid functions
if dm.command.mdadm then
  local rname, rmembers, rlevel
  tab_section.tabs.raid = translate("Raid")
  local r = m:section(SimpleSection, translate("RAID Creation"))
  r.template="diskman/cbi/xnullsection"
  r.config = "raid"
  local r_name = r:option(Value, "_name", translate("Raid Name"))
  r_name.placeholder = "/dev/md0"
  r_name.write = function(self, section, value)
    rname = value
  end
  local r_level = r:option(ListValue, "_level", translate("Raid Level"))
  local valid_raid = luci.util.exec("lsmod | grep md_mod")
  if valid_raid:match("linear") then
    r_level:value("linear", "Linear")
  end
  if valid_raid:match("raid456") then
    r_level:value("5", "Raid 5")
    r_level:value("6", "Raid 6")
  end
  if valid_raid:match("raid1") then
    r_level:value("1", "Raid 1")
  end
  if valid_raid:match("raid0") then
    r_level:value("0", "Raid 0")
  end
  if valid_raid:match("raid10") then
    r_level:value("10", "Raid 10")
  end
  r_level.write = function(self, section, value)
    rlevel = value
  end
  local r_member = r:option(DynamicList, "_member", translate("Raid Member"))
  for dev, info in pairs(disks) do
    if not info.inuse and  #info.partitions == 0  then
        r_member:value(info.path, info.path.. " ".. info.size_formated)
    end
    for i, v in ipairs(info.partitions) do
      if not v.inuse then
        r_member:value("/dev/".. v.name, "/dev/".. v.name .. " ".. v.size_formated)
      end
    end
  end
  r_member.write = function(self, section, value)
    rmembers = value
  end
  local r_create = r:option(Button, "_create")
  r_create.render = function(self, section, scope)
    self.title = " "
    self.inputtitle = translate("Create Raid")
    self.inputstyle = "add"
    Button.render(self, section, scope)
  end
  r_create.write = function(self, section, value)
    -- mdadm --create --verbose /dev/md0 --level=stripe --raid-devices=2 /dev/sdb6 /dev/sdc5
    local res = dm.create_raid(rname, rlevel, rmembers)
    if res:match("^ERR") then
      m.errmessage = translate(res)
      return
    end
    dm.gen_mdadm_config()
    luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
  end
end

-- mount point
local mount_point = dm.get_mount_points()
local _mount_point = {}
table.insert( mount_point, { device = 0 } )
local table_mp = m:section(Table, mount_point, translate("Mount Point"))
table_mp.config = "mount_point"
local v_device = table_mp:option(Value, "device", translate("Device"))
v_device.render = function(self, section, scope)
  if mount_point[section].device == 0 then
    self.template = "cbi/value"
    self.forcewrite = true
    Value.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    DummyValue.render(self, section, scope)
  end
end
v_device.write = function(self, section, value)
  _mount_point.device = value and value:gsub("%s+", "") or ""
end
local v_fs = table_mp:option(Value, "fs", translate("File System"))
v_fs.render = function(self, section, scope)
  if mount_point[section].device == 0 then
    self.template = "cbi/value"
    self:value("auto", "auto")
    self.default = "auto"
    self.forcewrite = true
    Value.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    DummyValue.render(self, section, scope)
  end
end
v_fs.write = function(self, section, value)
  _mount_point.fs = value and value:gsub("%s+", "") or ""
end
local v_mount_option = table_mp:option(Value, "mount_options", translate("Mount Options"))
v_mount_option.render = function(self, section, scope)
  if mount_point[section].device == 0 then
    self.template = "cbi/value"
    self.placeholder = "rw,noauto"
    self.forcewrite = true
    Value.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    local mp = mount_point[section].mount_options
    mount_point[section].mount_options = nil
    for k in mp:gmatch("([^,]+)") do
      mount_point[section].mount_options = mount_point[section].mount_options and mount_point[section].mount_options .. "," or ""
      if #mount_point[section].mount_options > 50 then mount_point[section].mount_options = mount_point[section].mount_options.. " " end
      mount_point[section].mount_options= mount_point[section].mount_options.. k
    end
    -- mount_point[section].mount_options = #mount_point[section].mount_options > 50 and mount_point[section].mount_options:sub(1,50) .. "..." or mount_point[section].mount_options
    DummyValue.render(self, section, scope)
  end
end
v_mount_option.write = function(self, section, value)
  _mount_point.mount_options = value and value:gsub("%s+", "") or ""
end
local v_mount_point = table_mp:option(Value, "mount_point", translate("Mount Point"))
v_mount_point.render = function(self, section, scope)
  if mount_point[section].device == 0 then
    self.template = "cbi/value"
    self.placeholder = "/media/diskX"
    self.forcewrite = true
    Value.render(self, section, scope)
  else
    self.template = "cbi/dvalue"
    DummyValue.render(self, section, scope)
  end
end
v_mount_point.write = function(self, section, value)
  _mount_point.mount_point = value
end
local btn_umount = table_mp:option(Button, "_mount", translate("Mount"))
btn_umount.forcewrite = true
btn_umount.render = function(self, section, scope)
  if mount_point[section].device == 0 then
    self.inputtitle = translate("Mount")
    btn_umount.inputstyle = "add"
  else
    self.inputtitle = translate("Umount")
    btn_umount.inputstyle = "remove"
  end
  Button.render(self, section, scope)
end
btn_umount.write = function(self, section, value)
  local res
  if value == translate("Mount") then
    luci.util.exec("mkdir -p ".. _mount_point.mount_point)
    res = luci.util.exec("mount ".. _mount_point.device .. (_mount_point.fs and (" -t ".. _mount_point.fs )or "") .. (_mount_point.mount_options and (" -o " .. _mount_point.mount_options.. " ") or  " ").._mount_point.mount_point .. " 2>&1")
  elseif value == translate("Umount") then
    res = luci.util.exec("umount "..mount_point[section].mount_point .. " 2>&1")
  end
  if res:match("^mount:") then
    m.errmessage = luci.util.pcdata(res)
  else
    luci.http.redirect(luci.dispatcher.build_url("admin/system/diskman"))
  end
end

-- -- btrfs
if dm.command.btrfs then
  tab_section.tabs.btrfs = translate("Btrfs")
  local btrfs_devices = {}
  local table_btrfs = m:section(Table, btrfs_devices, translate("Btrfs"))
  table_btrfs.config = "btrfs"
end
return m
