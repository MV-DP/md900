# Melchior FRANZ, < mfranz # aon : at >

#Thanks to Melchior for a wonderful heli-two-engine code! 

if (!contains(globals, "cprint"))
	var cprint = func nil;

var devel = !!getprop("devel");
var quickstart = !!getprop("quickstart");

var sin = func(a) math.sin(a * D2R);
var cos = func(a) math.cos(a * D2R);
var pow = func(v, w) math.exp(math.ln(v) * w);
var npow = func(v, w) v ? math.exp(math.ln(abs(v)) * w) * (v < 0 ? -1 : 1) : 0;
var clamp = func(v, min = 0, max = 1) v < min ? min : v > max ? max : v;
var normatan = func(x, slope = 1) math.atan2(x, slope) * 2 / math.pi;
var bell = func(x, spread = 2) pow(math.e, -(x * x) / spread);
var max = func(a, b) a > b ? a : b;
var min = func(a, b) a < b ? a : b;

# liveries =========================================================
aircraft.livery.init("Aircraft/md900/Models/liveries");

#doors=========================
leftFrontDoor = aircraft.door.new( "/sim/model/md900/door-positions/leftFrontDoor", 4, 0 );
rightFrontDoor = aircraft.door.new( "/sim/model/md900/door-positions/rightFrontDoor", 4, 0 );
leftBackDoor = aircraft.door.new( "/sim/model/md900/door-positions/leftBackDoor", 4, 0 );
rightBackDoor = aircraft.door.new( "/sim/model/md900/door-positions/rightBackDoor", 4, 0 );
leftRearDoor = aircraft.door.new( "/sim/model/md900/door-positions/leftRearDoor", 4, 0 );
rightRearDoor = aircraft.door.new( "/sim/model/md900/door-positions/rightRearDoor", 4, 0 );

# timers ============================================================
aircraft.timer.new("/sim/time/hobbs/helicopter", nil).start();

# strobes ===========================================================
var strobe_switch = props.globals.initNode("controls/lighting/strobe", 1, "BOOL");
aircraft.light.new("sim/model/md900/lighting/strobe-top", [0.05, 1.00], strobe_switch);
aircraft.light.new("sim/model/md900/lighting/strobe-bottom", [0.05, 1.03], strobe_switch);

# beacons ===========================================================
var beacon_switch = props.globals.initNode("controls/lighting/beacon", 1, "BOOL");
aircraft.light.new("sim/model/md900/lighting/beacon-top", [0.62, 0.62], beacon_switch);
aircraft.light.new("sim/model/md900/lighting/beacon-bottom", [0.63, 0.63], beacon_switch);


# nav lights ========================================================
var nav_light_switch = props.globals.initNode("controls/lighting/nav-lights", 1, "BOOL");
var visibility = props.globals.getNode("environment/visibility-m", 1);
var sun_angle = props.globals.getNode("sim/time/sun-angle-rad", 1);
var nav_lights = props.globals.getNode("sim/model/md900/lighting/nav-lights", 1);

#var nav_light_loop = func {
#	if (nav_light_switch.getValue())
#		nav_lights.setValue(visibility.getValue() < 5000 or sun_angle.getValue() > 1.4);
#	else
#		nav_lights.setValue(0);
#
#	settimer(nav_light_loop, 3);
#}

#nav_light_loop();



# doors =============================================================
var Doors = {
	new: func {
		var m = { parents: [Doors] };
		m.active = 0;
		m.list = [];
		foreach (var d; props.globals.getNode("sim/model/md900/doors").getChildren("door"))
			append(m.list, aircraft.door.new(d, 2.5));
		return m;
	},
	next: func {
		me.select(me.active + 1);
	},
	previous: func {
		me.select(me.active - 1);
	},
	select: func(which) {
		me.active = which;
		if (me.active < 0)
			me.active = size(me.list) - 1;
		elsif (me.active >= size(me.list))
			me.active = 0;
		gui.popupTip("Selecting " ~ me.list[me.active].node.getNode("name").getValue());
	},
	toggle: func {
		me.list[me.active].toggle();
	},
	reset: func {
		foreach (var d; me.list)
			d.setpos(0);
	},
};



# fuel ==============================================================

# density = 6.682 lb/gal [Flight Manual Section 9.2]
# avtur/JET A-1/JP-8
var FUEL_DENSITY = getprop("/consumables/fuel/tank/density-ppg"); # pound per gallon
var GAL2LB = FUEL_DENSITY;
var LB2GAL = 1 / GAL2LB;
var KG2GAL = KG2LB * LB2GAL;
var GAL2KG = 1 / KG2GAL;



var Tank = {
	new: func(n) {
		var m = { parents: [Tank] };
		m.capacity = n.getNode("capacity-gal_us").getValue();
		m.level_galN = n.initNode("level-gal_us", m.capacity);
		m.level_lbN = n.getNode("level-lbs");
		m.consume(0);
		return m;
	},
	level: func {
		return me.level_galN.getValue();
	},
	consume: func(amount) { # US gal (neg. values for feeding)
		var level = me.level();
		if (amount > level)
			amount = level;
		level -= amount;
		if (level > me.capacity)
			level = me.capacity;
		me.level_galN.setDoubleValue(level);
		me.level_lbN.setDoubleValue(level * GAL2LB);
		return amount;
	},
};



var fuel = {
	init: func {
		var fuel = props.globals.getNode("/consumables/fuel");
		me.pump_capacity = 6.6 * L2GAL / 60; # same pumps for transfer and supply; from md900 p2: 6.6 l/min older versions/ 12.5l/min newer versions
		me.total_galN = fuel.getNode("total-fuel-gals", 1);
		me.total_lbN = fuel.getNode("total-fuel-lbs", 1);
		me.total_normN = fuel.getNode("total-fuel-norm", 1);
		me.main = Tank.new(fuel.getNode("tank[0]"));
		me.rsupply = Tank.new(fuel.getNode("tank[1]"));
		me.lsupply = Tank.new(fuel.getNode("tank[2]"));
		
		

		var sw = props.globals.getNode("/controls/switches");
		setlistener(sw.initNode("fuel/transfer-pump[0]", 1, "BOOL"), func(n) me.trans1 = n.getValue(), 1);
		setlistener(sw.initNode("fuel/transfer-pump[1]", 1, "BOOL"), func(n) me.trans2 = n.getValue(), 1);
		setlistener("/sim/freeze/fuel", func(n) me.freeze = n.getBoolValue(), 1);
		me.capacity = me.main.capacity + me.rsupply.capacity + me.lsupply.capacity;

		me.update(0);
	},
	update: func(dt) {

		# transfer pumps (feed supply from main)
		var free1 = me.rsupply.capacity - me.rsupply.level() ;
		var free2 = me.lsupply.capacity - me.lsupply.level() ;
		
		if (free1 > 0) {
			var trans_flow1 = (me.trans1 + me.trans2) * me.pump_capacity;
			me.rsupply.consume(-me.main.consume(min(trans_flow1 * dt, free1)));
		}
		if (free2 > 0) {
			var trans_flow2 = (me.trans1 + me.trans2) * me.pump_capacity;
			me.lsupply.consume(-me.main.consume(min(trans_flow2 * dt, free2)));
		}
                
		# low fuel warning [POH "General Description" 0.28a]
		#var time = elapsedN.getValue();
		#if (time > me.warntime and me.bsupply.level() * GAL2KG < 60) {
		#	screen.log.write("LOW FUEL WARNING", 1, 0, 0);
		#	me.warntime = time + screen.log.autoscroll * 2;
		#}

		var level = me.main.level() + me.rsupply.level() + me.lsupply.level();
		me.total_galN.setDoubleValue(level);
		me.total_lbN.setDoubleValue(level * GAL2LB);
		me.total_normN.setDoubleValue(level / me.capacity);
	},
	level: func {
		return me.rsupply.level() + me.lsupply.level();
		
	},
	
	consume: func(amount) {
		return me.freeze ? 0 : me.rsupply.consume(amount) + me.lsupply.consume(amount);
	},
};



# engines/rotor =====================================================
var rotor_rpm = props.globals.getNode("rotors/main/rpm");
var torque = props.globals.getNode("rotors/gear/total-torque", 1);
var collective = props.globals.getNode("controls/engines/engine[0]/throttle");
var turbine = props.globals.getNode("sim/model/md900/turbine-rpm-pct", 1);
var torque_pct = props.globals.getNode("sim/model/md900/torque-pct", 1);
var torque2_pct = props.globals.getNode("sim/model/md900/torque2-pct", 1);
var torque3_pct = props.globals.getNode("sim/model/md900/torque-oei", 1);
var torque4_pct = props.globals.getNode("sim/model/md900/torque-aeo", 1);
var target_rel_rpm = props.globals.getNode("controls/rotor/reltarget", 1);
var max_rel_torque = props.globals.getNode("controls/rotor/maxreltorque", 1);




var Engine = {
	new: func(n) {
		var m = { parents: [Engine] };
		m.in = props.globals.getNode("controls/engines", 1).getChild("engine", n, 1);
		m.out = props.globals.getNode("engines", 1).getChild("engine", n, 1);
		m.airtempN = props.globals.getNode("/environment/temperature-degc");

		# input
		m.ignitionN = m.in.initNode("ignition", 0, "BOOL");
		m.starterN = m.in.initNode("starter", 0, "BOOL");
		m.powerN = m.in.initNode("power", 0);
		m.magnetoN = m.in.initNode("magnetos", 1, "INT");

		# output
		m.runningN = m.out.initNode("running", 0, "BOOL");
		m.n1_pctN = m.out.initNode("n1-pct", 0);
		m.n2_pctN = m.out.initNode("n2-pct", 0);
		m.n1N = m.out.initNode("n1-rpm", 0);
		m.n2N = m.out.initNode("n2-rpm", 0);
		m.totN = m.out.initNode("tot-degc", m.airtempN.getValue());

		m.starterLP = aircraft.lowpass.new(3);
		m.n1LP = aircraft.lowpass.new(4);
		m.n2LP = aircraft.lowpass.new(4);
		setlistener("/sim/signals/reinit", func(n) n.getValue() or m.reset(), 1);
		m.timer = aircraft.timer.new("/sim/time/hobbs/turbines[" ~ n ~ "]", 10);
		m.running = 0;
		m.fuelflow = 0;
		m.n1 = -1;
		m.up = -1;
		return m;
	},
	reset: func {
		me.magnetoN.setIntValue(1);
		me.ignitionN.setBoolValue(0);
		me.starterN.setBoolValue(0);
		me.powerN.setDoubleValue(0);
		me.runningN.setBoolValue(me.running = 0);
		me.starterLP.set(0);
		me.n1LP.set(me.n1 = 0);
		me.n2LP.set(me.n2 = 0);
	},
	update: func(dt, trim = 0) {
		var starter = me.starterLP.filter(me.starterN.getValue() * 0.19);	# starter 15-20% N1max
		me.powerN.setValue(me.power = clamp(me.powerN.getValue()));
		var power = me.power * 1.00 + trim;					# 100% = N2% in flight position

		if (me.running)
			power += (1 - collective.getValue()) * 0.00;			# droop compensator
		if (power > 1.04)
			power = 1.04;							# overspeed restrictor

		me.fuelflow = 0;
		if (!me.running) {
			if (me.n1 > 0.05 and power > 0.05 and me.ignitionN.getValue()) {
				me.runningN.setBoolValue(me.running = 1);
				me.timer.start();
			}

		} elsif (power < 0.05 or !fuel.level()) {
			me.runningN.setBoolValue(me.running = 0);
			me.timer.stop();

		} else {
			me.fuelflow = power;
		}

		var lastn1 = me.n1;
		me.n1 = me.n1LP.filter(max(me.fuelflow, starter));
		me.n2 = me.n2LP.filter(me.n1);
		me.up = me.n1 - lastn1;

		# temperature
		if (me.fuelflow > me.pos.idle)
			var target = 440 + (779 - 440) * (0.00 + me.fuelflow - me.pos.idle) / (me.pos.flight - me.pos.idle);
		else
			var target = 440 * (0.00 + me.fuelflow) / me.pos.idle;

		if (me.n1 < 0.4 and me.fuelflow - me.n1 > 0.001) {
			target += (me.fuelflow - me.n1) * 7000;
			if (target > 980)
				target = 980;
		}

		var airtemp = me.airtempN.getValue();
		if (target < airtemp)
			target = airtemp;

		var decay = (me.up > 0 ? 10 : me.n1 > 0.02 ? 0.01 : 0.001) * dt;
		me.totN.setValue((me.totN.getValue() + decay * target) / (1 + decay));

		# constant 150 kg/h for now (both turbines)
		fuel.consume(150 * KG2GAL * me.fuelflow * dt / 3600);

		# derived gauge values
		me.n1_pctN.setDoubleValue(me.n1 * 100);
		me.n2_pctN.setDoubleValue(me.n2 * 100);
		me.n1N.setDoubleValue(me.n1 * 58000);
		me.n2N.setDoubleValue(me.n2 * 39130);
	},
	setpower: func(v) {
		var target = (int((me.power + 0.15) * 3) + v) / 3;
		var time = abs(me.power - target) * 4;
		interpolate(me.powerN, target, time);
	},
	adjust_power: func(delta, mode = 0) {
		if (delta) {
			var power = me.powerN.getValue();
			if (me.power_min == nil) {
				if (delta > 0) {
					if (power < me.pos.idle) {
						me.power_min = me.pos.cutoff;
						me.power_max = me.pos.idle;
					} else {
						me.power_min = me.pos.idle;
						me.power_max = me.pos.flight;
					}
				} else {
					if (power > me.pos.idle) {
						me.power_max = me.pos.flight;
						me.power_min = me.pos.idle;
					} else {
						me.power_max = me.pos.idle;
						me.power_min = me.pos.cutoff;
					}
				}
			}
			me.powerN.setValue(power = clamp(power + delta, me.power_min, me.power_max));
			return power;
		} elsif (mode) {
			me.power_min = me.power_max = nil;
		}
	},
	pos: { cutoff: 0, idle: 0.70, flight: 1 },
};



var engines = {
	init: func {
		me.engine = [Engine.new(0), Engine.new(1)];
		me.trimN = props.globals.initNode("/controls/engines/power-trim");
		me.balanceN = props.globals.initNode("/controls/engines/power-balance");
		me.commonrpmN = props.globals.initNode("/engines/engine/rpm");
				
	},
	reset: func {
		me.engine[0].reset();
		me.engine[1].reset();
	},
	update: func(dt) {
	
		
		# each starter button disables ignition switch of opposite engine
		if (me.engine[0].starterN.getValue())
			me.engine[1].ignitionN.setBoolValue(0);
		if (me.engine[1].starterN.getValue())
			me.engine[0].ignitionN.setBoolValue(0);

		# update engines
		#var n2trimfunction = 3;
		var trim = (me.trimN.getValue() * 0.1);
		var balance = me.balanceN.getValue() * 0.1;
		me.engine[0].update(dt, trim - balance);
		me.engine[1].update(dt, trim + balance);


		# set rotor
		var n2relrpm = max(me.engine[0].n2, me.engine[1].n2);
		var n2max = (me.engine[0].n2 +  me.engine[1].n2) / 2;
		target_rel_rpm.setValue(n2relrpm);
		max_rel_torque.setValue(n2max);
		

		me.commonrpmN.setValue(n2max * 33290); # attitude indicator needs pressure

		# Warning Box Type K-DW02/01
		if (n2max > 0.67) { # 0.63?
			setprop("sim/sound/warn2600", n2max > 1.08);
			setprop("sim/sound/warn650", abs(me.engine[0].n2 - me.engine[1].n2) > 0.12
					or n2max > 0.75 and n2max < 0.95);
		} else {
			setprop("sim/sound/warn2600", 0);
			setprop("sim/sound/warn650", 0);
		}
	},
	adjust_power: func(delta, mode = 0) {
		if (!delta) {
			engines.engine[0].adjust_power(0, mode);
			engines.engine[1].adjust_power(0, mode);
		} else {
			var p = [0, 0];
			for (var i = 0; i < 2; i += 1)
				if (controls.engines[i].selected.getValue())
					p[i] = engines.engine[i].adjust_power(delta);
			gui.popupTip(sprintf("power lever %d%%", 100 * max(p[0], p[1])));
		}
	},
	quickstart: func { # development only
		me.engine[0].n1LP.set(1);
		me.engine[0].n2LP.set(1);
		me.engine[1].n1LP.set(1);
		me.engine[1].n2LP.set(1);
		procedure.step = 1;
		procedure.next();
	},
};



var vert_speed_fpm = props.globals.initNode("/velocities/vertical-speed-fpm");

if (devel) {
	setprop("/instrumentation/altimeter/setting-inhg", getprop("/environment/pressure-inhg"));

	setlistener("/sim/signals/fdm-initialized", func {
		settimer(func {
			screen.property_display.x = 760;
			screen.property_display.y = 200;
			screen.property_display.format = "%.3g";
			screen.property_display.add(
				rotor_rpm,
				torque_pct,
				target_rel_rpm,
				max_rel_torque,
				"/controls/engines/power-trim",
				"/controls/engines/power-balance",
				"/consumables/fuel/total-fuel-gals",
				"L",
				engines.engine[0].runningN,
				engines.engine[0].ignitionN,
				"/controls/engines/engine[0]/power",
				engines.engine[0].n1_pctN,
				engines.engine[0].n2_pctN,
				engines.engine[0].totN,
				#engines.engine[0].n1N,
				#engines.engine[0].n2N,
				"R",
				engines.engine[1].runningN,
				engines.engine[1].ignitionN,
				"/controls/engines/engine[1]/power",
				engines.engine[1].n1_pctN,
				engines.engine[1].n2_pctN,
				engines.engine[1].totN,
				#engines.engine[1].n1N,
				#engines.engine[1].n2N,
				"X",
				"/sim/model/gross-weight-kg",
				"/position/altitude-ft",
				"/position/altitude-agl-ft",
				"/instrumentation/altimeter/indicated-altitude-ft",
				"/environment/temperature-degc",
				vert_speed_fpm,
				"/velocities/airspeed-kt",
			);
		}, 1);
	});
}



var mouse = {
	init: func {
		me.x = me.y = nil;
		me.savex = nil;
		me.savey = nil;
		setlistener("/sim/startup/xsize", func(n) me.centerx = int(n.getValue() / 2), 1);
		setlistener("/sim/startup/ysize", func(n) me.centery = int(n.getValue() / 2), 1);
		setlistener("/devices/status/mice/mouse/mode", func(n) me.mode = n.getValue(), 1);
		setlistener("/devices/status/mice/mouse/button[1]", func(n) {
			me.mmb = n.getValue();
			if (me.mode)
				return;
			if (me.mmb) {
				engines.adjust_power(0, 1);
				me.savex = me.x;
				me.savey = me.y;
				gui.setCursor(me.centerx, me.centery, "none");
			} else {
				gui.setCursor(me.savex, me.savey, "pointer");
			}
		}, 1);
		setlistener("/devices/status/mice/mouse/x", func(n) me.x = n.getValue(), 1);
		setlistener("/devices/status/mice/mouse/y", func(n) me.update(me.y = n.getValue()), 1);
	},
	update: func {
		if (me.mode or !me.mmb)
			return;

		if (var dy = -me.y + me.centery)
			engines.adjust_power(dy * 0.005);

		#gui.setCursor(me.centerx, me.centery);
	},
};



var power = func(v) {
	if (controls.engines[0].selected.getValue())
		engines.engine[0].setpower(v);
	if (controls.engines[1].selected.getValue())
		engines.engine[1].setpower(v);
}



var startup = func {
	if (procedure.stage < 0) {
		procedure.step = 1;
		procedure.next();
	}
}


var shutdown = func {
	if (procedure.stage > 0) {
		procedure.step = -1;
		procedure.next();
	}
}


var procedure = {
	stage: -999,
	step: nil,
	loopid: 0,
	reset: func {
		me.loopid += 1;
		me.stage = -999;
		step = nil;
		engines.reset();
	},
	next: func(delay = 0) {
		if (crashed)
			return;
		if (me.stage < 0 and me.step > 0 or me.stage > 0 and me.step < 0)
			me.stage = 0;

		settimer(func { me.stage += me.step; me.process(me.loopid) }, delay * !quickstart);
	},
	process: func(id) {
		id == me.loopid or return;
		# startup
		if (me.stage == 1) {
			cprint("", "1: press start button #1 -> spool up turbine #1 to N1 8.6--15%");
			setprop("/controls/rotor/brake", 0);
			engines.engine[0].ignitionN.setValue(1);
			engines.engine[0].starterN.setValue(1);
			me.next(4);

		} elsif (me.stage == 2) {
			cprint("", "2: move power lever #1 forward -> fuel injection");
			engines.engine[0].powerN.setValue(0.13);
			me.next(2.5);

		} elsif (me.stage == 3) {
			cprint("", "3: turbine #1 ignition (wait for EGT stabilization)");
			me.next(4.5);

		} elsif (me.stage == 4) {
			cprint("", "4: move power lever #1 to idle position -> engine #1 spools up to N1 74%");
			engines.engine[0].powerN.setValue(0.74);
			me.next(5);

		} elsif (me.stage == 5) {
			cprint("", "5: release start button #1\n");
			engines.engine[0].starterN.setValue(0);
			engines.engine[0].ignitionN.setValue(0);
			me.next(3);

		} elsif (me.stage == 6) {
			cprint("", "6: press start button #2 -> spool up turbine #2 to N1 8.6--15%");
			engines.engine[1].ignitionN.setValue(1);
			engines.engine[1].starterN.setValue(1);
			me.next(5);

		} elsif (me.stage == 7) {
			cprint("", "7: move power lever #2 forward -> fuel injection");
			engines.engine[1].powerN.setValue(0.13);
			me.next(2);

		} elsif (me.stage == 8) {
			cprint("", "8: turbine #2 ignition (wait for EGT stabilization)");
			me.next(5);

		} elsif (me.stage == 9) {
			cprint("", "9: move power lever #2 to idle position -> engine #2 spools up to N1 74%");
			engines.engine[1].powerN.setValue(0.74);
			me.next(8);

		} elsif (me.stage == 10) {
			cprint("", "10: release start button #2\n");
			engines.engine[1].starterN.setValue(0);
			engines.engine[1].ignitionN.setValue(0);
			me.next(1);

		} elsif (me.stage == 11) {
			cprint("", "11: move both power levers forward -> turbines spool up to 100%");
			engines.engine[0].powerN.setValue(1);
			engines.engine[1].powerN.setValue(1);

		# shutdown
		} elsif (me.stage == -1) {
			cprint("", "-1: power lever in idle position; cool engines");
			engines.engine[0].starterN.setValue(0);
			engines.engine[1].starterN.setValue(0);
			engines.engine[0].ignitionN.setValue(0);
			engines.engine[1].ignitionN.setValue(0);
			engines.engine[0].powerN.setValue(0.74);
			engines.engine[1].powerN.setValue(0.74);
			me.next(40);

		} elsif (me.stage == -2) {
			cprint("", "-2: engines shut down");
			engines.engine[0].powerN.setValue(0);
			engines.engine[1].powerN.setValue(0);
			me.next(40);

		} elsif (me.stage == -3) {
			cprint("", "-3: rotor brake\n");
			setprop("/controls/rotor/brake", 1);
		}
	},
};



# torquemeter
var torque_val = 0;
torque.setDoubleValue(0);

#max tqr value = 598600
var update_torque = func(dt) {
	var f = dt / (0.2 + dt);
	torque_val = torque.getValue() * f + torque_val * (1 - f);
	torque_pct.setDoubleValue(torque_val / 6500);
	
}



# blade vibration absorber pendulum
var pendulum = props.globals.getNode("/sim/model/md900/absorber-angle-deg", 1);
var update_absorber = func {
	pendulum.setDoubleValue(90 * clamp(abs(rotor_rpm.getValue()) / 90));
}



var vibration = { # and noise ...
	init: func {
		me.lonN = props.globals.initNode("/rotors/main/vibration/longitudinal");
		me.latN = props.globals.initNode("/rotors/main/vibration/lateral");
		me.soundN = props.globals.initNode("/sim/sound/vibration");
		me.airspeedN = props.globals.getNode("/velocities/airspeed-kt");
		me.vertspeedN = props.globals.getNode("/velocities/vertical-speed-fps");

		me.groundspeedN = props.globals.getNode("/velocities/groundspeed-kt");
		me.speeddownN = props.globals.getNode("/velocities/speed-down-fps");
		me.angleN = props.globals.initNode("/velocities/descent-angle-deg");
		me.dir = 0;
	},
	update: func(dt) {
		var airspeed = me.airspeedN.getValue();
		if (airspeed > 145) { # overspeed vibration
			var frequency = 2000 + 500 * rand();
			var v = 0.49 + 0.5 * normatan(airspeed - 160, 10);
			var intensity = v;
			var noise = v * internal;

		} elsif (airspeed > 0.01) { # Blade Vortex Interaction (BVI)    10 deg, 85 kts max?
			var frequency = rotor_rpm.getValue() * 4 * 60;
			var down = me.speeddownN.getValue() * FT2M;
			var level = me.groundspeedN.getValue() * NM2M / 3600;
			me.angleN.setDoubleValue(var angle = math.atan2(down, level) * R2D);
			var speed = math.sqrt(level * level + down * down) * MPS2KT;
			angle = bell(angle - 8, 13);
			speed = bell(speed - 65, 450);
			var v = angle * speed;
			var intensity = v * 0.10;
			var noise = v * (1 - internal * 0.4);

		} else { # hover
			var rpm = rotor_rpm.getValue();
			var frequency = rpm * 4 * 60;
			var coll = bell(collective.getValue(), 0.5);
			var ias = bell(airspeed, 600);
			var vert = bell(me.vertspeedN.getValue() * 0.5, 400);
			var rpm = 0.477 + 0.5 * normatan(rpm - 350, 30) * 1.025;
			var v = coll * ias * vert * rpm;
			var intensity = v * 0.10;
			var noise = v * (1 - internal * 0.4);
		}

		me.dir += dt * frequency;
		me.lonN.setValue(cos(me.dir) * intensity);
		me.latN.setValue(sin(me.dir) * intensity);
		me.soundN.setValue(noise);
	},
};




# sound =============================================================

# stall sound
var stall = props.globals.getNode("rotors/main/stall", 1);
var stall_filtered = props.globals.getNode("rotors/main/stall-filtered", 1);

var stall_val = 0;
stall.setDoubleValue(0);

var update_stall = func(dt) {
	var s = stall.getValue();
	if (s < stall_val) {
		var f = dt / (0.3 + dt);
		stall_val = s * f + stall_val * (1 - f);
	} else {
		stall_val = s;
	}
	var c = collective.getValue();
	stall_filtered.setDoubleValue(stall_val + 0.006 * (1 - c));
}



# skid slide sound
var Skid = {
	new: func(n) {
		var m = { parents: [Skid] };
		var soundN = props.globals.getNode("sim/model/md900/sound", 1).getChild("slide", n, 1);
		var gearN = props.globals.getNode("gear", 1).getChild("gear", n, 1);

		m.compressionN = gearN.getNode("compression-norm", 1);
		m.rollspeedN = gearN.getNode("rollspeed-ms", 1);
		m.frictionN = gearN.getNode("ground-friction-factor", 1);
		m.wowN = gearN.getNode("wow", 1);
		m.volumeN = soundN.getNode("volume", 1);
		m.pitchN = soundN.getNode("pitch", 1);

		m.compressionN.setDoubleValue(0);
		m.rollspeedN.setDoubleValue(0);
		m.frictionN.setDoubleValue(0);
		m.volumeN.setDoubleValue(0);
		m.pitchN.setDoubleValue(0);
		m.wowN.setBoolValue(1);
		m.self = n;
		return m;
	},
	update: func {
		me.wow = me.wowN.getValue();
		if (me.wow < 0.5)
			return me.volumeN.setDoubleValue(0);

		var rollspeed = abs(me.rollspeedN.getValue());
		me.pitchN.setDoubleValue(rollspeed * 0.6);

		var s = normatan(20 * rollspeed);
		var f = clamp((me.frictionN.getValue() - 0.5) * 2);
		var c = clamp(me.compressionN.getValue() * 2);
		var vol = s * f * c;
		me.volumeN.setDoubleValue(vol > 0.1 ? vol : 0);
		#if (!me.self) {
		#	cprint("33;1", sprintf("S=%0.3f  F=%0.3f  C=%0.3f  >>  %0.3f", s, f, c, s * f * c));
		#}
	},
};

var skids = [];
for (var i = 0; i < 4; i += 1)
	append(skids, Skid.new(i));

#var antislide = props.globals.initNode("/gear/antislide");
var update_slide = func {
	var wow = 0;
	foreach (var s; skids) {
		s.update();
		wow += s.wow;
	}
	#antislide.setDoubleValue(wow > 0 ? 1 - rotor_rpm.getValue() / 10 : 0);
}

var internal = 1;
setlistener("sim/current-view/view-number", func {
	internal = getprop("sim/current-view/internal");
}, 1);


var volume_internal = props.globals.getNode("sim/model/md900/sound/volume_internal", 1);
var volume_external = props.globals.getNode("sim/model/md900/sound/volume_external", 1);
var update_volume = func {

	if (internal == 1){
	volume_internal.setDoubleValue(0.8);
	volume_external.setDoubleValue(0);
}else{
	volume_internal.setDoubleValue(0);
	volume_external.setDoubleValue(1);
}

}



# crash handler =====================================================
var crash = func {
	if (arg[0]) {
		# crash
		setprop("sim/model/md900/tail-angle-deg", 35);
		setprop("sim/model/md900/shadow", 0);
		setprop("sim/model/md900/doors/door[0]/position-norm", 0.2);
		setprop("sim/model/md900/doors/door[1]/position-norm", 0.9);
		setprop("sim/model/md900/doors/door[2]/position-norm", 0.2);
		setprop("sim/model/md900/doors/door[3]/position-norm", 0.6);
		setprop("sim/model/md900/doors/door[4]/position-norm", 0.1);
		setprop("sim/model/md900/doors/door[5]/position-norm", 0.05);
		setprop("rotors/main/rpm", 0);
		setprop("rotors/main/blade[0]/flap-deg", -60);
		setprop("rotors/main/blade[1]/flap-deg", -50);
		setprop("rotors/main/blade[2]/flap-deg", -40);
		setprop("rotors/main/blade[3]/flap-deg", -30);
		setprop("rotors/main/blade[0]/incidence-deg", -30);
		setprop("rotors/main/blade[1]/incidence-deg", -20);
		setprop("rotors/main/blade[2]/incidence-deg", -50);
		setprop("rotors/main/blade[3]/incidence-deg", -55);
		setprop("rotors/tail/rpm", 0);
		strobe_switch.setValue(0);
		beacon_switch.setValue(0);
		nav_light_switch.setValue(0);
		engines.engine[0].n2_pctN.setValue(0);
		engines.engine[1].n2_pctN.setValue(0);
		torque_pct.setValue(torque_val = 0);
		stall_filtered.setValue(stall_val = 0);

	} else {
		# uncrash (for replay)
		setprop("sim/model/md900/tail-angle-deg", 0);
		setprop("sim/model/md900/shadow", 1);
		doors.reset();
		setprop("rotors/tail/rpm", 2219);
		setprop("rotors/main/rpm", 442);
		for (i = 0; i < 4; i += 1) {
			setprop("rotors/main/blade[" ~ i ~ "]/flap-deg", 0);
			setprop("rotors/main/blade[" ~ i ~ "]/incidence-deg", 0);
		}
		strobe_switch.setValue(1);
		beacon_switch.setValue(1);
		engines.engine[0].n2_pct.setValue(100);
		engines.engine[1].n2_pct.setValue(100);
	}
}




# "manual" rotor animation for flight data recorder replay ============
var rotor_step = props.globals.getNode("sim/model/md900/rotor-step-deg");
var blade1_pos = props.globals.getNode("rotors/main/blade[0]/position-deg", 1);
var blade2_pos = props.globals.getNode("rotors/main/blade[1]/position-deg", 1);
var blade3_pos = props.globals.getNode("rotors/main/blade[2]/position-deg", 1);
var blade4_pos = props.globals.getNode("rotors/main/blade[3]/position-deg", 1);
var rotorangle = 0;

var rotoranim_loop = func {
	var i = rotor_step.getValue();
	if (i >= 0.0) {
		blade1_pos.setValue(rotorangle);
		blade2_pos.setValue(rotorangle + 90);
		blade3_pos.setValue(rotorangle + 180);
		blade4_pos.setValue(rotorangle + 270);
		rotorangle += i;
		settimer(rotoranim_loop, 0.1);
	}
}

var init_rotoranim = func {
	if (rotor_step.getValue() >= 0.0)
		settimer(rotoranim_loop, 0.1);
}












# view management ===================================================

var elapsedN = props.globals.getNode("/sim/time/elapsed-sec", 1);
var flap_mode = 0;
var down_time = 0;
controls.flapsDown = func(v) {
	if (!flap_mode) {
		if (v < 0) {
			down_time = elapsedN.getValue();
			flap_mode = 1;
			dynamic_view.lookat(
					5,     # heading left
					-20,   # pitch up
					0,     # roll right
					0.2,   # right
					0.6,   # up
					0.85,  # back
					0.2,   # time
					55,    # field of view
			);
		} elsif (v > 0) {
			flap_mode = 2;
			gui.popupTip("AUTOTRIM", 1e10);
			aircraft.autotrim.start();
		}

	} else {
		if (flap_mode == 1) {
			if (elapsedN.getValue() < down_time + 0.2)
				return;

			dynamic_view.resume();
		} elsif (flap_mode == 2) {
			aircraft.autotrim.stop();
			gui.popdown();
		}
		flap_mode = 0;
	}
}


# register function that may set me.heading_offset, me.pitch_offset, me.roll_offset,
# me.x_offset, me.y_offset, me.z_offset, and me.fov_offset
#
dynamic_view.register(func {
	var lowspeed = 1 - normatan(me.speedN.getValue() / 50);
	var r = sin(me.roll) * cos(me.pitch);

	me.heading_offset =						# heading change due to
		(me.roll < 0 ? -50 : -30) * r * abs(r);			#    roll left/right

	me.pitch_offset =						# pitch change due to
		(me.pitch < 0 ? -50 : -50) * sin(me.pitch) * lowspeed	#    pitch down/up
		+ 15 * sin(me.roll) * sin(me.roll);			#    roll

	me.roll_offset =						# roll change due to
		-15 * r * lowspeed;					#    roll
});







# main() ============================================================
var delta_time = props.globals.getNode("/sim/time/delta-sec", 1);
var hi_heading = props.globals.getNode("/instrumentation/heading-indicator/indicated-heading-deg", 1);
var vertspeed = props.globals.initNode("/velocities/vertical-speed-fps");
var gross_weight_lb = props.globals.initNode("/fdm/yasim/gross-weight-lbs");
var gross_weight_kg = props.globals.initNode("/sim/model/gross-weight-kg");
props.globals.getNode("/instrumentation/adf/rotation-deg", 1).alias(hi_heading);


var main_loop = func {
	props.globals.removeChild("autopilot");
	if (replay)
		setprop("/position/gear-agl-m", getprop("/position/altitude-agl-ft") * 0.3 - 1.2);
	vert_speed_fpm.setDoubleValue(vertspeed.getValue() * 60);
	gross_weight_kg.setDoubleValue(gross_weight_lb.getValue() or 0 * LB2KG);


	var dt = delta_time.getValue();
	update_torque(dt);
	update_stall(dt);
	update_slide();
	update_volume();
	update_absorber();
	fuel.update(dt);
	engines.update(dt);
	vibration.update(dt);
	settimer(main_loop, 0);
}


var replay = 0;
var crashed = 0;

var doors = Doors.new();
#var config_dialog = gui.Dialog.new("/sim/gui/dialogs/md900/config/dialog", "Aircraft/md900/Dialogs/config.xml");


setlistener("/sim/signals/fdm-initialized", func {
	gui.menuEnable("autopilot", 0);
	init_rotoranim();
	vibration.init();
	engines.init();
	fuel.init();
	mouse.init();

	
	

	collective.setDoubleValue(1);

	setlistener("/sim/signals/reinit", func(n) {
		n.getBoolValue() and return;
		cprint("32;1", "reinit");
		procedure.reset();
		collective.setDoubleValue(1);
		aircraft.livery.rescan();
		reconfigure();
		crashed = 0;
	});

	setlistener("sim/crashed", func(n) {
		cprint("31;1", "crashed ", n.getValue());
		engines.engine[0].timer.stop();
		engines.engine[1].timer.stop();
		if (n.getBoolValue())
			crash(crashed = 1);
	});

	setlistener("/sim/freeze/replay-state", func(n) {
		replay = n.getValue();
		cprint("33;1", replay ? "replay" : "pause");
		if (crashed)
			crash(!n.getBoolValue())
	});

	main_loop();
	if (devel and quickstart)
		engines.quickstart();
     });
# livery/configuration ==============================================

#aircraft.livery.init("Aircraft/md900/Models/Variants", "sim/model/md900/name");




# toggle floats (inflate/repack)
# mhab 20131104
toggle_floats = func () {

  if ( getprop("/sim/model/md900/emergencyfloats") ) {
    if ( getprop("/controls/gear/floats-inflat") ) {
      if ( getprop("gear/gear[0]/wow") or getprop("gear/gear[1]/wow") or getprop("gear/gear[2]/wow") or getprop("gear/gear[3]/wow") ) {
        setprop("/controls/gear/floats-inflat",0);
        setprop("/controls/gear/floats-armed",0);
      } else {
        gui.popupTip("Repack only possible on ground",1);
      }
    } else {
      if ( getprop("/controls/gear/floats-armed") ) {
        setprop("/controls/gear/floats-inflat",1);
      } else {
        gui.popupTip("Floats are not armed",1);
      }
    }
  }
}




