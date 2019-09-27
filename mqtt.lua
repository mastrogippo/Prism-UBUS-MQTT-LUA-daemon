-- UBUS to MQTT bridge to interface Prism with OpenEnergyMonitor
-- Copyright (C) 2019 Mastro Gippo
-- 
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later
-- version.
-- 
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of  MERCHANTABILITY or FITNESS
-- FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License along with
-- this program.  If not, see <http://www.gnu.org/licenses/>.

local ins = require "inspect"
require "ubus"
require "uloop"

uloop.init()

local loadc = require "loadc"
mqtt = require("mosquitto")
client = mqtt.new()

local status
local conn
local conf = loadc.load();

print(_VERSION)

-- mosquitto_pub -h 192.168.1.141 -u 'emonpi' -P 'emonpimqtt2016' -t 'emon/prism/setcurrent' -m 9.0

client.ON_CONNECT = function(r_ok, r_res, r_desc)

	if (r_ok == false) then
		--TODO: LOG_ERROR
		print("Connection error: " .. r_res .. " (" .. r_desc .. ")");
		os.exit()
	end
	
	print("connected2!")
	
	local mid = client:subscribe(conf["local_sub_topic"]);
	print("SUB mid = " .. mid)
end

-- client.DISCONNECT = function()
	-- --print("published!")
	-- --client:disconnect()
	-- print("disconnected!")
-- end

client.ON_MESSAGE = function(mid, topic, payload)
    print(topic, payload)
	local cA = payload;
	status = conn:call("evse.control", "port_current_max_change", {port=1,current_max=cA})
	if status == nil then
		print("UBUS ERROR - no answer from EVSE")
		do return end
	else
		print("status=" .. ins.inspect(status));
	end
end

client.ON_PUBLISH = function()
	--print("published!")
	--client:disconnect()
	--print("disconnected!")
end

--local str = ins.inspect(conf)
--print(str)

--connect UBUS
conn = ubus.connect()
if not conn then
    error("Failed to connect to ubusd")
	do return end
end

--read status
status = conn:call("evse.control", "get_status", {})--{ name = "eth0" })
if status == nil then
	print("UBUS ERROR - no answer from EVSE")
	do return end
else
	print("status=" .. ins.inspect(status));
end

--UBUS notify
local sub = {
	notify = function( msg )

		if msg['voltage_now'] == nil then
			print("status_message");
			do return end
		end

		--print("MSG: "  .. ins.inspect(msg));
		if msg["port"] == 1 then
			if msg['status'] == "error" then
				local mid = client:publish(conf["local_base_topic"] .. "error", msg['error']);
				--print("mid = " .. mid)
			else
				-- openevse/amp Measured current in milliamps
				-- openevse/wh Calculated watthours for the current session
				-- openevse/temp1 Sensor value in 10th degree C (if installed)
				-- openevse/temp2 Sensor value in 10th degree C (if installed)
				-- openevse/temp3 Sensor value in 10th degree C (if installed)
				-- openevse/pilot Pilot current sent to vehicle in Amps (6-80)
				-- openevse/state EVSE State 1–Ready, 2-Connected, 3-Charging, 4-Error
				-- openevse/freeram WiFi free Ram
				-- openevse/divertmode Divert Mode 1–Normal, 2–Eco Divert
				-- Published to broker every 5 seconds
				-- openevse/chargerate Calculated power available from Grid I/E Topic
				-- openevse/grid_ie Last Value received on Grid I/E Topic

				local mid = client:publish(conf["local_base_topic"] .. "amp", msg['current_now'] * 1000);
				--print("mid amp= " .. mid)
				mid = client:publish(conf["local_base_topic"] .. "wh", msg['power_now']);
				--print("mid wh= " .. mid)
				--mid = client:publish(conf["local_base_topic"] .. "temp1", msg['power_now']);
				--print("mid wh= " .. mid)
				mid = client:publish(conf["local_base_topic"] .. "pilot", msg['current_max']);
				--print("mid p= " .. mid);
				
				if msg["status"] == "idle" then mid = client:publish(conf["local_base_topic"] .. "state", 1);
				elseif msg["status"] == "waiting" then mid = client:publish(conf["local_base_topic"] .. "state", 2);
				elseif msg["status"] == "charging" then mid = client:publish(conf["local_base_topic"] .. "state", 3);
				else mid = client:publish(conf["local_base_topic"] .. "state", 4); --ERROR! Fix
				end
				--print("mid s= " .. mid);
				

				--print("status = " .. status['result']['ports'][1]['status']);
				--mid = client:publish(conf["local_base_topic"] .. "tate", status['result']['ports'][1]['status']);
				--print("mid = " .. mid);
			end
		end

		-- print("Count: ", msg["status"])
	end,
}


--print("MQTT Connecting")
client:login_set(conf["local_user"],conf["local_password"])
--broker = --arg[1] -- defaults to "localhost" if arg not set
client:connect(conf["local_address"], conf["local_port"])
--client:loop(2000)
--client:loop_forever()

conn:subscribe( "evse.control", sub )
client:loop(1000)
client:loop_start()
uloop.run()

--::fine::

print("exit?")

--client:loop_forever()