#
# Flight Control System by Tatsuhiro Nishioka 
# $Id$
#
#This one simulates a P/R and Jaw SAS

var FCSFilter = {
  new : func(input_path, output_path) {
    var obj = { parents : [FCSFilter], 
                input_path : input_path,
                output_path : output_path };
    obj.axis_conv = {'roll' : 'aileron', 'pitch' : 'elevator', 'yaw' : 'rudder' };
    obj.body_conv = {'roll' : 'v', 'pitch' : 'u' };
    obj.last_body_fps = {'roll' : 0.0, 'pitch' : 0.0 };
    obj.last_pos = {'roll' : 0.0, 'pitch' : 0.0, 'yaw' : 0.0};
    return obj;
  },

  # read input command for a given axis
  read : func(axis) {
    if (me.input_path == nil or me.input_path == "") {
      return getprop("/controls/flight/" ~ me.axis_conv[axis]);
    } else { 
      var value = getprop(me.input_path ~ "/" ~ axis);
      value = int(value * 1000) / 1000.0;
    }
  },

  # write output command for a given axis
  # this will be the output of an next command filter (like SAS)
  write : func(axis, value) {
    if (me.output_path == nil or me.output_path == '') {
      setprop("/controls/flight/fcs/" ~ axis, me.limit(value, 1.0));
    } else {
      setprop(me.output_path ~ "/" ~ axis, me.limit(value, 1.0));
    }
  },

  toggleFilterStatus : func(name) {
    var messages = ["disengaged", "engaged"];
    var path = "/controls/flight/fcs/" ~ name ~ "-enabled";
    var status = getprop(path);
    setprop(path, 1 - status);
    #screen.log.write(name ~ " " ~ messages[1 - status]);
  },

  getStatus : func(name) {
    var path = "/controls/flight/fcs/" ~ name ~ "-enabled";
    return getprop(path);
  },

  limit : func(value, range) {
    if (value > range) {
      return range;
    } elsif (value < -range) {
      return - range;
    }
    return value;
  },

  max : func(val1, val2) {
    return (val1 > val2) ? val1 : val2;
  },

  min : func(val1, val2) {
    return (val1 > val2) ? val2 : val1;
  },

  calcCounterBodyFPS : func(axis, input, offset_deg) {
    var position = getprop("/orientation/" ~ axis ~ "-deg");
    var body_fps = 0;
    var last_body_fps = me.last_body_fps[axis];
    var reaction_gain = 0;
    var heading = getprop("/orientation/heading-deg");
    var wind_speed_fps = getprop("/environment/wind-speed-kt") * 1.6878099;
    var wind_direction = getprop("/environment/wind-from-heading-deg");
    var wind_direction -= heading;
    var rate = getprop("/orientation/" ~ axis ~ "-rate-degps");
    var gear_pos = getprop("/gear/gear[0]/compression-norm") + getprop("/gear/gear[1]/compression-norm");
    var counter_fps = 0;
    var fps_axis = me.body_conv[axis]; # convert from {roll, pitch} to {u, v}
    var target_pos = offset_deg;
    var brake_deg = 0;

    body_fps = getprop("/velocities/" ~ fps_axis ~ "Body-fps");
    if (axis == 'roll') {
      var wind_fps = math.sin(wind_direction / 180 * math.pi) * wind_speed_fps; 
    } else {
      var wind_fps = math.cos(wind_direction / 180 * math.pi) * wind_speed_fps; 
    }
    var brake_freq = getprop("/controls/flight/fcs/gains/afcs/fps-" ~ axis ~ "-brake-freq");
    var brake_gain = getprop("/controls/flight/fcs/gains/afcs/fps-brake-gain-" ~ axis);
    body_fps -= wind_fps;
    var dfps = body_fps - me.last_body_fps[axis];
    var fps_coeff = getprop("/controls/flight/fcs/gains/afcs/fps-" ~ axis ~ "-coeff");
    target_pos -= int(body_fps * 100) / 100 * fps_coeff;
    if (axis == 'roll' and gear_pos > 0.0 and position > 0) {
      target_pos -= position * gear_pos / 5;
    }
    reaction_gain = getprop("/controls/flight/fcs/gains/afcs/fps-reaction-gain-" ~ axis);
    var brake_sensitivity = (axis == 'roll') ? 1 : 1;
    if (math.abs(position + rate / brake_freq * brake_sensitivity) > math.abs(target_pos)) {
      if (math.abs(dfps) > 1) {
        dfps = 1;
      }
      var error_deg = target_pos - position;
      brake_deg = (error_deg - rate / brake_freq) * math.abs(dfps * 10) * brake_gain;
      if (target_pos > 0) {
        brake_deg = me.min(brake_deg, 0);
      } else {
        brake_deg = me.max(brake_deg, 0);
      }
    }
    counter_fps = me.limit((target_pos + brake_deg) * reaction_gain, 1.0);

    setprop("/controls/flight/fcs/afcs/ah-" ~ fps_axis ~ "body-fps", body_fps);
    setprop("/controls/flight/fcs/afcs/ah-" ~ fps_axis ~ "body-wind-fps", wind_fps);
    setprop("/controls/flight/fcs/afcs/ah-" ~ axis ~ "-target-deg", target_pos);
    setprop("/controls/flight/fcs/afcs/ah-" ~ axis ~ "-rate", rate);
    setprop("/controls/flight/fcs/afcs/ah-delta-" ~ fps_axis ~ "body-fps", dfps);
    setprop("/controls/flight/fcs/afcs/ah-" ~ axis ~ "-brake-deg", brake_deg);

    setprop("/controls/flight/fcs/afcs/counter-fps-" ~ axis, counter_fps);
    me.last_pos[axis] = position;
    me.last_body_fps[axis] = body_fps;
    return me.limit(counter_fps + input * 0.2, 1.0);
  },

};

#
# AFCS : Automatic Flight Control System
#
var AFCS = {
  new : func(input_path, output_path) {
    var obj = FCSFilter.new(input_path, output_path);
    obj.parents = [FCSFilter, AFCS];
    setprop("/controls/flight/fcs/auto-hover-enabled", 0);
    setprop("/controls/flight/fcs/gains/afcs/fps-brake-gain-pitch", 1.8);
    setprop("/controls/flight/fcs/gains/afcs/fps-brake-gain-roll", 0.8);
    setprop("/controls/flight/fcs/gains/afcs/fps-pitch-brake-freq", 3);
    setprop("/controls/flight/fcs/gains/afcs/fps-pitch-coeff", -0.95);
    setprop("/controls/flight/fcs/gains/afcs/fps-pitch-offset-deg", 0.9);
    setprop("/controls/flight/fcs/gains/afcs/fps-reaction-gain-pitch", -0.8);
    setprop("/controls/flight/fcs/gains/afcs/fps-reaction-gain-roll", 0.3436);
    setprop("/controls/flight/fcs/gains/afcs/fps-roll-brake-freq", 8);
    setprop("/controls/flight/fcs/gains/afcs/fps-roll-coeff", 0.8);
    setprop("/controls/flight/fcs/gains/afcs/fps-roll-offset-deg", -0.8);
    return obj;
  },

  toggleAutoHover : func() {
    me.toggleFilterStatus("auto-hover");
  },

  toggleAirSpeedLock : func() {
    me.toggleFilterStatus("air-speed-lock");
  },

  toggleHeadingLock : func() {
    me.toggleFilterStatus("heading-lock");
  },

  toggleAltitudeLock : func() {
    me.toggleFilterStatus("altitude-lock");
  },

  # 
  # auto hover : locks vBody_fps and uBody_fps regardless of wind speed/direction
  # 
  autoHover : func(axis, input) {
    if (axis == 'yaw') {
      return input;
    } else {
      var offset_deg = getprop("/controls/flight/fcs/gains/afcs/fps-" ~ axis ~ "-offset-deg");
      return me.calcCounterBodyFPS(axis, input, offset_deg);
    }
  },

  altitudeLock : func(axis, input) {
    # not implemented yet
    return input;
  },

  headingLock : func(axis, input) {
    # not implementet yet
    return input;
  },

  apply : func(axis) {
    var input = me.read(axis);
    var hover_status = me.getStatus("auto-hover");
    if (hover_status == 0) {
      me.write(axis, input);
      return;
    }
    me.write(axis, me.autoHover(axis, input));
  }
};

# 
# SAS : Stability Augmentation System - a rate damper
# 
var SAS = {
  # 
  # new
  #   initial_gains: hash of initial gains for rate damping
  #   sensitivities: hash of minimum rates (deg/sec) that enables rate damper
  #   authority_limit: shows how much SAS can take over control
  #                    0 means no stability control, 1.0 means SAS fully takes over pilot control
  #   input_path: is a base path to input axis; nil for using raw input from KB/JS
  #   output_path: is a base path to output axis; nis for using /controls/flight/fcs
  # 
  #   with input_path / output_path, you can connect SAS, CAS, and more control filters
  #
  new : func(initial_gains, sensitivities, authority_limit, input_path, output_path) {
    var obj = FCSFilter.new(input_path, output_path);
    obj.parents = [FCSFilter, SAS];
    obj.authority_limit = authority_limit;
    obj.sensitivities = sensitivities; 
    obj.initial_gains = initial_gains;
    props.globals.getNode("/controls/flight/fcs/gains/sas", 1).setValues(obj.initial_gains);
    setprop("/controls/flight/fcs/sas-enabled", 1);
    return obj;
  },

  toggleEnable : func() {
    me.toggleFilterStatus("sas");
  },

  # 
  # calcGain - get gain for each axis based on air speed and dynamic pressure
  #   axis: one of 'roll', 'pitch', or 'yaw'
  # 
  calcGain : func(axis) {
    var mach = getprop("/velocities/mach");
    var initial_gain = getprop("/controls/flight/fcs/gains/sas/" ~ axis);
    var gain = initial_gain - 0.1 * mach * mach;
    if (math.abs(gain) < math.abs(initial_gain) * 0.01 or gain * initial_gain < 0) {
      gain = initial_gain * 0.01;
    }
    return gain;
  }, 

  calcAuthorityLimit : func() {
    var mach = getprop("/velocities/mach");
    var min_mach = 0.038;
    var limit = me.authority_limit;
    if (math.abs(mach < min_mach)) {
      limit += (min_mach - math.abs(mach))  / min_mach * (1 - me.authority_limit) * 0.95;
    }
    setprop("/controls/flight/fcs/gains/sas/authority-limit", limit);
    return limit;
  },

  # 
  # apply - apply SAS damper to a given input axis
  #   axis: one of 'roll', 'pitch', or 'yaw'
  # 
  apply : func(axis) {
    var status = me.getStatus("sas");
    var input = me.read(axis);
    if (status == 0) {
      me.write(axis, input);
      return;
    }
    var mach = getprop("/velocities/mach");
    var value = 0;
    var rate = getprop("/orientation/" ~ axis ~ "-rate-degps");
    var gain = me.calcGain(axis);
    var limit = me.calcAuthorityLimit();
    if (math.abs(rate) >= me.sensitivities[axis]) {
      value = - gain * rate;
      if (value > limit) {
        value = limit;
      } elsif (value < - limit) {
        value = - limit;
      } 
    }
    me.write(axis, value + input);
  }
};

# 
# CAS : Control Augmentation System - makes your aircraft more meneuverable
# 
var CAS = {
  new : func(input_gains, output_gains, sensitivities, input_path, output_path) {
    var obj = FCSFilter.new(input_path, output_path);
    obj.parents = [FCSFilter, CAS];
    obj.sensitivities = sensitivities; 
    obj.input_gains = input_gains;
    obj.output_gains = output_gains;
    props.globals.getNode("/controls/flight/fcs/gains/cas/input", 1).setValues(obj.input_gains);
    props.globals.getNode("/controls/flight/fcs/gains/cas/output", 1).setValues(obj.output_gains);
    setprop("/autopilot/locks/altitude", '');
    setprop("/autopilot/locks/heading", '');
    setprop("/controls/flight/fcs/cas-enabled", 1);
    return obj;
  },

  calcRollRateAdjustment : func {
    var position = getprop("/orientation/roll-deg");
    return math.abs(math.sin(position / 180 * math.pi)) / 6;
  },

  calcSideSlipAdjustment : func {
    var mach = getprop("/velocities/mach");
    var slip = getprop("/orientation/side-slip-deg");
    if (mach < 0.015) { # works only if air speed > 10kt
      slip = 0;
    }
    var anti_slip_gain = getprop("/controls/flight/fcs/gains/cas/output/anti-side-slip-gain");
    var roll_deg = getprop("/orientation/roll-deg");
    var gain_adjuster = me.min(math.abs(mach) / 0.060, 1) * me.limit(0.2 + math.sqrt(math.abs(roll_deg)/10), 3);
    anti_slip_gain *= gain_adjuster;
    setprop("/controls/flight/fcs/cas/anti-side-slip", slip * anti_slip_gain);
    return slip * anti_slip_gain;
  },
  
  # FIXME: command for CAS is just a temporal one
  calcCommand: func (axis, input) {
    var output = 0;
    var mach = getprop("/velocities/mach");
    var input_gain = me.calcGain(axis);
    var output_gain = getprop("/controls/flight/fcs/gains/cas/output/" ~ axis);
    var target_rate = input * input_gain;
    var rate = getprop("/orientation/" ~ axis ~ "-rate-degps");
    var drate = target_rate - rate;
    var locks = {'pitch' : getprop("/autopilot/locks/altitude"),
                 'roll' : getprop("/autopilot/locks/heading")};
    setprop("/controls/flight/fcs/cas/target_" ~ axis ~ "rate", target_rate);
    setprop("/controls/flight/fcs/cas/delta_" ~ axis, drate);
    
    if (axis == 'roll' or axis == 'pitch') {
       if (math.abs(input > 0.7) or locks[axis] != '') {
         output = drate * output_gain;
       } else {
         output = me.calcAttitudeCommand(axis);
      }
      if (axis == 'roll' and math.abs(mach) < 0.035) {
        # FIXME: I don't know if OH-1 has this one
        output += me.calcCounterBodyFPS(axis, input, -0.8);
      }
    } elsif (axis == 'yaw') {
      output = drate * output_gain + me.calcSideSlipAdjustment();
    } else {
      output = drate * output_gain;
    }
    return output;
  },

  toggleEnable : func() {
    me.toggleFilterStatus("cas");
  },

  calcAttitudeCommand : func(axis) {
    var input_gain = getprop("/controls/flight/fcs/gains/cas/input/attitude-" ~ axis);
    var output_gain = getprop("/controls/flight/fcs/gains/cas/output/" ~ axis);
    var brake_freq = getprop("/controls/flight/fcs/gains/cas/output/" ~ axis ~ "-brake-freq");
    var brake_gain = getprop("/controls/flight/fcs/gains/cas/output/" ~ axis ~ "-brake");
    var trim = getprop("/controls/flight/" ~ me.axis_conv[axis] ~ "-trim");

    var current_deg = getprop("/orientation/" ~ axis ~ "-deg");
    var rate = getprop("/orientation/" ~ axis ~ "-rate-degps");
    var target_deg = (me.read(axis) + trim) * input_gain;
    var command_deg = 0;
    if (target_deg != 0) {
      command_deg = (0.094 * math.ln(math.abs(target_deg)) + 0.53) * target_deg;
    }

    var error_deg = command_deg - current_deg;
    var brake_deg = (error_deg - rate / brake_freq) * math.abs(error_deg) * brake_gain;

    if (command_deg > 0) {
      brake_deg = me.min(brake_deg, 0);
    } else {
      brake_deg = me.max(brake_deg, 0);
    }

    var monitor_prefix = me.output_path ~ "/" ~ axis;
    setprop(monitor_prefix ~ "-target_deg", target_deg);
    setprop(monitor_prefix ~ "-error_deg", error_deg);
    setprop(monitor_prefix ~ "-brake_deg", brake_deg);
    setprop(monitor_prefix ~ "-deg", current_deg);
    setprop(monitor_prefix ~ "-rate", -rate);

    return (error_deg + brake_deg) * output_gain;
  },

  # FixMe: gain should be calculated using both speed and dynamic pressure
  calcGain : func(axis) {
    var mach = getprop("/velocities/mach");
    var input_gain = getprop("/controls/flight/fcs/gains/cas/input/" ~ axis);
    var gain = input_gain;
    if (axis == 'pitch') {
      gain += 0.1 * mach * mach;
    } elsif (axis== 'yaw') {
      gain *= ((1 - mach) * (1 - mach));
    }
    if (gain * input_gain < 0.0 ) {
      gain = 0;
    }
    return gain;
  }, 

  apply : func(axis) {
    var input = me.read(axis);
    var status = me.getStatus("cas");
    var cas_command = 0;
    # FIXME : hmm, a bit nasty. CAS should be enabled even with auto-hover....
    if (status == 0 or (me.getStatus("auto-hover") == 1 and axis != 'yaw')) {
      me.write(axis, input);
      return;
    }
    cas_command = me.calcCommand(axis, input);
    me.write(axis, cas_command);
  }
};

#
# Tail hstab, "stabilator," for stabilize the nose 
#
var Stabilator = {
  new : func() {
    var obj = { parents : [Stabilator] };
    setprop("/controls/flight/fcs/gains/stabilator", -1.8);
    setprop("/controls/flight/fcs/auto-stabilator", 1);
                   #   0    10   20    30   40   50   60   70   80   90  100  110  120  130  140  150  160, 170, 180, .....
   me.gainTable =  [-0.9, -0.8, 0.1, -0.5, 0.0, 0.7, 0.8, 0.9, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.8, 0.6, 0.4, 0.2, -1.0];
    return obj;
  },

  toggleManual : func {
    var status = getprop("/controls/flight/fcs/auto-stabilator");
    getprop("/controls/flight/fcs/auto-stabilator", 1 - status);
  },
  
  apply : func(delta) {
    setprop("/controls/flight/fcs/auto-stabilator", 0);
    var value = getprop("/controls/flight/fcs/stabilator");
    getprop("/controls/flight/fcs/stabilator", value + delta);
  },

  calcPosition : func() {
    var speed = getprop("/velocities/mach") / 0.001497219; # in knot
    var index = int(math.abs(speed) / 10);
    if (index >= size(me.gainTable) - 1) {
      index = size(me.gainTable) - 2;
    }
    var mod = math.mod(int(math.abs(speed)), 10);
    var position = me.gainTable[index] * ((10 - mod) / 10) + me.gainTable[index-1] * (mod) / 10;
    if (speed < -20) {
      position = - position;
    }
    return position;
  },

  update : func() {
    var status = getprop("/controls/flight/fcs/auto-stabilator");
    if (status == 0) {
      return;
    }
    var gain = getprop("/controls/flight/fcs/gains/stabilator");
    var mach = getprop("/velocities/mach");
    var throttle = getprop("/controls/flight/throttle");
    var stabilator_norm = 0;

    stabilator_norm = me.calcPosition();   
    setprop("/controls/flight/fcs/stabilator", stabilator_norm);
  }
};

var TailRotorCollective = {
  new : func(minimum=0.10, maximum=1.0, low_limit=0.00011, high_limit=0.0035) {
    var obj = FCSFilter.new("/controls/engines/engine[1]", "/controls/flight/fcs/tail-rotor");
    obj.parents = [FCSFilter, TailRotorCollective];
    obj.adjuster = 0.0;
    setprop("/controls/flight/fcs/tail-rotor/src-minimum", minimum);
    setprop("/controls/flight/fcs/tail-rotor/src-maximum", maximum);
    setprop("/controls/flight/fcs/tail-rotor/low-limit", low_limit);
    setprop("/controls/flight/fcs/tail-rotor/high-limit", high_limit);
    setprop("/controls/flight/fcs/gains/tail-rotor/error-adjuster-gain", -0.5);
    return obj;
  },

  update : func() {
    var throttle = me.read("throttle");
    var pedal_pos_deg = getprop("/controls/flight/fcs/yaw");
    var cas_input = cas.read('yaw');
    var cas_input_gain = cas.calcGain('yaw');
    var target_rate = cas_input * cas_input_gain;
    var rate = getprop("/orientation/yaw-rate-degps");
    var error_rate = getprop("/controls/flight/fcs/cas/delta_yaw");
    var error_adjuster_gain = getprop("/controls/flight/fcs/gains/tail-rotor/error-adjuster-gain");

    var minimum = getprop("/controls/flight/fcs/tail-rotor/src-minimum");
    var maximum = getprop("/controls/flight/fcs/tail-rotor/src-maximum");
    var low_limit = getprop("/controls/flight/fcs/tail-rotor/low-limit");
    var high_limit = getprop("/controls/flight/fcs/tail-rotor/high-limit");
    var output = 0;
    var range = maximum - minimum;
    
    if (throttle < minimum) {
      output = low_limit;
    } elsif (throttle > maximum) {
      output = high_limit;
    } else {
      output = low_limit  + (throttle - minimum) / range * (high_limit - low_limit);
    } 

    # CAS driven tail rotor thrust adjuster
    me.adjuster = error_rate * error_adjuster_gain;
    me.adjuster = me.limit(me.adjuster, 0.3);
    output += me.adjuster;

    setprop("/controls/flight/fcs/tail-rotor/error-rate", error_rate);
    setprop("/controls/flight/fcs/tail-rotor/adjuster", me.adjuster);

    me.write("throttle", output);
  }
};

var sas = nil;
var cas = nil;
var afcs = nil;
var stabilator = nil;
var tail = nil;
var count = 0;


var sensitivities = {'roll' : 40.0, 'pitch' : -40.0, 'yaw' : 10.0 };
var sas_initial_gains = {'roll' : 0.0072, 'pitch' : -0.0082, 'yaw' : 0.02 };
var cas_input_gains = {'roll' : 30, 'pitch' : -60, 'yaw' : 30, 
                       'attitude-roll' : 80, 'attitude-pitch' : -80 };
var cas_output_gains = {'roll' : 0.06, 'pitch' : -0.1, 'yaw' : 0.5, 
                        'roll-brake-freq' : 10, 'pitch-brake-freq' : 3, 
                        'roll-brake' : 0.4, 'pitch-brake' : 6, 
                        'anti-side-slip-gain' : -4.5};
var update = func {
  count += 1;
  # AFCS, CAS, and SAS run at 60Hz
  if (math.mod(count, 2) == 0) {
    return;
  }
  cas.apply('roll');
  cas.apply('pitch');
  cas.apply('yaw');

  afcs.apply('roll');
  afcs.apply('pitch');
  afcs.apply('yaw');

  sas.apply('roll');
  sas.apply('pitch');
  sas.apply('yaw');
  stabilator.update();
  tail.update();
}

var initialize = func {
  cas = CAS.new(cas_input_gains, cas_output_gains, sensitivities, nil, "/controls/flight/fcs/cas");
  afcs = AFCS.new("/controls/flight/fcs/cas", "/controls/flight/fcs/afcs");
  sas = SAS.new(sas_initial_gains, sensitivities, 3, "/controls/flight/fcs/afcs", "/controls/flight/fcs");
  stabilator = Stabilator.new();
  tail = TailRotorCollective.new();
  setlistener("/rotors/main/cone-deg", update);
}

_setlistener("/sim/signals/fdm-initialized", initialize);

