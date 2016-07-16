# functions for searchlight handling
# mhab 20140430

# Options dialog
var searchlight_options_dialog = gui.Dialog.new("/sim/gui/dialogs/searchlight/options/dialog", "Aircraft/ec130/Models/SearchLight/searchlight-options-dialog.xml");

# ===============================
# initialize Searchlight settings
# ===============================
#
# init at startup and after livery change
#
slight_init = func () {

  # init searchlight props
  setprop("/sim/model/searchlight/state",getprop("/sim/model/searchlight/state-default"));
  var trak = getprop("/sim/model/ec130/searchlight_a800");
  if ( !trak ) {
    setprop("/sim/model/searchlight/heading-deg",getprop("/sim/model/searchlight/sx16/heading-default-deg"));
  } else {
    setprop("/sim/model/searchlight/heading-deg",getprop("/sim/model/searchlight/a800/heading-default-deg"));
  }
  if ( !trak ) {
    setprop("/sim/model/searchlight/elevation-deg",getprop("/sim/model/searchlight/sx16/elevation-default-deg"));
  } else {
    setprop("/sim/model/searchlight/elevation-deg",getprop("/sim/model/searchlight/a800/elevation-default-deg"));
  }
  setprop("/sim/model/searchlight/filter-state",getprop("/sim/model/searchlight/filter-state-default"));
  setprop("/sim/model/searchlight/cone-visibility",getprop("/sim/model/searchlight/cone-visibility-default"));
  setprop("/sim/model/searchlight/active",0);
  setprop("/sim/model/searchlight/paused",0);

  # SX-16 filter is down by default
  setprop("/sim/model/searchlight/filter/position-norm", 0.0);
  setprop("/sim/model/searchlight/filter/move-direction", 1.0);

  # supply orientation for stabi
  slight_orientation();

  # stabilize A800 if active and light is on (not paused)
  if ( trak ) {
    # initialize stabi prop
    setprop("/sim/model/searchlight/stabi-active",1);

    # start stabilization
    stabilize_props();
  }
}

# ====================================
# set orientation for A800 Searchlight
# ====================================
#
# set orientation for stabi
#
slight_orientation = func () {

  # flag for A800 searchlight
  if ( getprop("/sim/model/ec130/searchlight_a800") ) {

    # heading
    var h = getprop("orientation/model/heading-deg");

    # pitch/elevation
    var p = getprop("orientation/model/pitch-deg");

    # roll
    var r = getprop("orientation/model/roll-deg");

    setprop("/sim/model/searchlight/orientation/heading-deg", h);
    setprop("/sim/model/searchlight/orientation/pitch-deg", p);
    setprop("/sim/model/searchlight/orientation/roll-deg", r);

  }
}

# =================
# reset Searchlight
# =================
#
#  - heading
#  - elevation
#
slight_reset = func () {

  var trak  = getprop("/sim/model/ec130/searchlight_a800");
  var stabi = getprop("/sim/model/searchlight/stabi-active");

  if ( !trak ) {
    var slew_rate = getprop("/sim/model/searchlight/sx16/slew-rate-deg");
  } else {
    var slew_rate = getprop("/sim/model/searchlight/a800/slew-rate-deg");
  }

  # interrupt stabi if active
  if ( trak ) { if ( stabi ) { setprop("/sim/model/searchlight/stabi-active",0) } }

  if ( !trak ) {
    var hd = getprop("/sim/model/searchlight/sx16/heading-default-deg");
  } else {
    var hd = getprop("/sim/model/searchlight/a800/heading-default-deg");
  }

  if ( trak ) {
    # A800 is stowed direction to back if not active
    if ( getprop("/sim/model/searchlight/active") ) {
      hd=hd+180;
    }
  }

  # amount of rotation
  var d = getprop("/sim/model/searchlight/heading-deg") - hd;
  if ( d < 0 ) { d *= -1.0 };

  var t = d/slew_rate;

  interpolate("/sim/model/searchlight/heading-deg", hd, t);

  if ( !trak ) {
    var ed = getprop("/sim/model/searchlight/sx16/elevation-default-deg");
  } else {
    var ed = getprop("/sim/model/searchlight/a800/elevation-default-deg");
  }
  var d = getprop("/sim/model/searchlight/elevation-deg") - ed;
  if ( d < 0 ) { d *= -1.0 };

  t = d/slew_rate;

  interpolate("/sim/model/searchlight/elevation-deg", ed, t);

  # continue stabi if active
  if ( trak ) { if ( stabi ) { setprop("/sim/model/searchlight/stabi-active",1) } }

  # supply orientation for stabi
  slight_orientation();
}

# ==============================
# power up/down with timer delay
# ==============================
#
slight_toggle_power = func () {

  var sd   = getprop("/sim/model/searchlight/state-default");
  var fd   = getprop("/sim/model/searchlight/filter-state-default");
  var trak = getprop("/sim/model/ec130/searchlight_a800");

  if ( !getprop("/sim/model/searchlight/active") ) {
    setprop("/sim/model/searchlight/paused",1);
    setprop("/sim/model/searchlight/active",1);
    if ( !trak ) {
      # SX16
      gui.popupTip("Searchlight is powered up ...",4);
      settimer( func {
        setprop("/sim/model/searchlight/paused",0);
        setprop("/sim/model/searchlight/cycle-state",1);
        setprop("/sim/model/searchlight/state",sd);
      }, 4);
    } else {
      # A800
      gui.popupTip("Searchlight is powered up and deployed ...",4);
      setprop("/sim/model/searchlight/cycle-state",1);
      setprop("/sim/model/searchlight/filter-state",fd);
      setprop("/sim/model/searchlight/state",sd);
      slight_reset();
      settimer( func {
        setprop("/sim/model/searchlight/paused",0);
      }, 3.5);
    }
  } else {
    setprop("/sim/model/searchlight/paused",1);
    if ( !trak ) {
      # SX16
      gui.popupTip("Searchlight is shut down ...",2);
      settimer( func {
        setprop("/sim/model/searchlight/active",0);
        setprop("/sim/model/searchlight/paused",0);
        setprop("/sim/model/searchlight/cycle-state",1);
      }, 2);
    } else {
      # A800
      gui.popupTip("Searchlight is shut down and stowed ...",2);
      setprop("/sim/model/searchlight/active",0);
      setprop("/sim/model/searchlight/paused",0);
      setprop("/sim/model/searchlight/cycle-state",1);
      slight_reset();
    }
  }
}

# ===========================================
# cycle Searchlight Distance (Lightcone Size)
# ===========================================
#
# do it as described in SX-16 manual:
#   --> on the original control is only 1 knob to change distance
#       and continued pressing it changes distance from near to far and back
#       no possibility to go both directions directly
#
slight_cycle = func () {

  var p = getprop("/sim/model/searchlight/state");
  var s = getprop("/sim/model/searchlight/cycle-state");
  if ( s == 1 ) {
    # cycle up
    if ( p < 4 ){
      p = p + 1;
    } else {
      p = p - 1;
      setprop("/sim/model/searchlight/cycle-state",0);
    }
  } else {
    # cycle down
    if ( p > 1 ){
      p = p - 1;
    } else {
      p = p + 1;
      setprop("/sim/model/searchlight/cycle-state",1);
    }
  }

  settimer( func{ setprop("/sim/model/searchlight/state",p); },0.4);

}

# =================================
# cycle Searchlight Cone Visibility
# =================================
#
# 0: off
# 1: low
# 2: medium
# 3: high
#
slight_cycle_cone_visibility = func () {

  var p = getprop("/sim/model/searchlight/cone-visibility");

  if ( p < 3 ) {
    p = p + 1;
  } else {
    p = 0;
  }

  interpolate("/sim/model/searchlight/cone-visibility", p, 0.7);
  setprop("/sim/model/searchlight/cone_flag_0",0);
  setprop("/sim/model/searchlight/cone_flag_1",0);
  setprop("/sim/model/searchlight/cone_flag_2",0);
  setprop("/sim/model/searchlight/cone_flag_3",0);

  if ( p == 0 ) {
    setprop("/sim/model/searchlight/cone_flag_0",1);
  }
  if ( p == 1 ) {
    setprop("/sim/model/searchlight/cone_flag_1",1);
  }
  if ( p == 2 ) {
    setprop("/sim/model/searchlight/cone_flag_2",1);
  }
  if ( p == 3 ) {
    setprop("/sim/model/searchlight/cone_flag_3",1);
  }
}

# =========================
# handle Searchlight Filter
# =========================
#
slight_toggle_cycle_filter = func () {

  if ( getprop("/sim/model/ec130/searchlight_a800") ) {
    #
    # cycle A800 filters
    # 1: white, 2: amber, 3: red, 4: IR filter
    # 1 sec delayed like original
    #
    if ( getprop("/sim/model/searchlight/active") ) {
      var p = getprop("/sim/model/searchlight/filter-state");
      var v = getprop("/sim/model/searchlight/cone-visibility");

      if ( p < 4 ) {
        p = p + 1;
      } else {
        p = 1;
      }

      if ( v ) {
        # fade out lightcone
        interpolate("/sim/model/searchlight/cone-visibility", 0.0, 0.5);
        # switch filter with delay (so it happens after fade out)
        # Rembrandt cone should fade and be off for a while
#        interpolate("/sim/model/searchlight/filter-state", p, 0.8);
        settimer( func{ setprop("/sim/model/searchlight/filter-state", p); },0.5);
        # fade in lightcone with delay (so it happens after fade out and switch)
        settimer( func{ interpolate("/sim/model/searchlight/cone-visibility", v, 0.5); },0.5);
      } else {
        settimer( func{ setprop("/sim/model/searchlight/filter-state", p); },1.0);
      }

    } else {
      gui.popupTip("Searchlight inactive, NO filter cycling possible !!!",2);
    }

  } else {
    #
    # toggle SX-16 filter down ... up is 0.0 ... 1.0
    #
    var pos = getprop("/sim/model/searchlight/filter/position-norm");
    var dir = getprop("/sim/model/searchlight/filter/move-direction");
    var time = 16.0;
    if (dir > 0.5) {
      # if direction up, move up
      interpolate("/sim/model/searchlight/filter/position-norm", 1.0, (1.0-pos)*time);
      setprop("/sim/model/searchlight/filter/move-direction", 0);
    } else {
      # if direction down, move down
      interpolate("/sim/model/searchlight/filter/position-norm", 0.0, pos*time);
      setprop("/sim/model/searchlight/filter/move-direction", 1);
    };
  }
}

# ==================
# rotate Searchlight
# ==================
#
# direction of rotation:
#
#   1 ... left (+)
#   2 ... right (-)
#   3 ... down (-)
#   4 ... up (+)
#
# Remark:
# Special Behavior of A800
# ------------------------
# A800 has two modes "stowed" vs. "deployed"
#
# Stowed Mode:
# In "stowed" mode light is OFF and it is directed to the back of the aircraft.
# It can me moved still.
#
# Deployed Mode:
# In "deployed" mode light is ON and it is directed to the front of the aircraft.
#
# As the heading is reversed by 180 deg between the two modes, the elevation control
# needs to invert the direction of movement.
#
slight_rotate = func (dir) {

  var trak   = getprop("/sim/model/ec130/searchlight_a800");
  var active = getprop("/sim/model/searchlight/active");
  var stabi  = getprop("/sim/model/searchlight/stabi-active");

  # calculate speed from slew-rate
  if ( !trak ) {
    var slew_rate = getprop("/sim/model/searchlight/sx16/slew-rate-deg");
  } else {
    var slew_rate = getprop("/sim/model/searchlight/a800/slew-rate-deg");
  }

  var head = getprop("/sim/model/searchlight/heading-deg");
  var elev = getprop("/sim/model/searchlight/elevation-deg");

  var delta = slew_rate / 18.0;

#  # different speed of SX-16 and A800
#  if ( !trak ) {
#    var delta = 1.0;
#  } else {
#    var delta = 4.0;
#  }

  # reverse movement
  if ( dir == 2 or dir == 3 ) { delta *= -1.0 }

  # heading
  if ( dir == 1 or dir == 2 ) {
    head += delta;
  }

  # elevation
  if ( dir == 3 or dir == 4 ) {
    elev += delta;
  }

  # limit movement and set props
  slight_limiter(head,elev,active,trak);

}

# ==========================
# limit searchlight movement
# ==========================
#
slight_limiter = func (head,elev,active,trak) {

  # get minimum heading
  if ( trak ) {
    var head_min = getprop("/sim/model/searchlight/a800/heading-min-deg");
    if ( !active ) { head_min -= 360 }
  } else {
    var head_min = getprop("/sim/model/searchlight/sx16/heading-min-deg");
  }

  # get maximum heading
  if ( trak ) {
    var head_max = getprop("/sim/model/searchlight/a800/heading-max-deg");
    if ( !active ) { head_max -= 360 }
  } else {
    var head_max = getprop("/sim/model/searchlight/sx16/heading-max-deg");
  }

  # get minimum elevation
  if ( trak ) {
    var elev_min = getprop("/sim/model/searchlight/a800/elevation-min-deg");
  } else {
    var elev_min = getprop("/sim/model/searchlight/sx16/elevation-min-deg");
  }

  # get maximum elevation
  if ( trak ) {
    var elev_max = getprop("/sim/model/searchlight/a800/elevation-max-deg");
  } else {
    var elev_max = getprop("/sim/model/searchlight/sx16/elevation-max-deg");
  }

  # limit heading
  if ( head > head_max ) { head = head_max }
  if ( head < head_min ) { head = head_min }

  # limit elevation
  if ( elev > elev_max ) { elev = elev_max }
  if ( elev < elev_min ) { elev = elev_min }

  setprop("/sim/model/searchlight/heading-deg", head);
  setprop("/sim/model/searchlight/elevation-deg", elev);

}

# ==================================
# stabilization for A800 Searchlight
# ==================================
#
#  Requirement: The searchlight shall compensate all changes
#     in heading/pitch/roll of the model, in this way realizing
#     a stabilization, as similar to the original as possible.
#
#     Level 1: compensation relative to heli flightpath
#              --> beam travels with the heli
#              Remark: seems this is what the original does
#
#     Level 2: related to a fixed point in scenery
#              --> beam stays fixed on a real world position
#              Remark: not sure if the original can do this,
#                      but original can be synced with the camera
#
#  Stabilization on/off:
#     For simplicity of implementation and due to lack of more detailed info
#     the stabilization is active as long as the searchlight is on.
#     If searchlight is off or paused stabilization is off.
#
#  Limitations: Roll cannot be fully compensated by a 2-axis gimbal.
#     Roll compensation is not necessary for heading 0/180 (no roll effect)
#     and critical if elevation is +/-90deg (max. roll effect).
#     For searchlight elev. +/-90 heading is undefined and pitch and
#     roll compensation fight against each other.
#
#       For heading 90/270 roll is compensated by elevation 1:1.
#       For heading 0/180 pitch is compensated by elevation 1:1.
#
#     All compensation can only work until gimbal limits are reached.
#     If gimbal limits are reached stabilization is not in effect until
#     any movement is possible again.
#
#  Problem:
#     Heading/Elevation of the lightbeam needs to be animated to counteract aircraft
#     movement "orientation/heading-deg", "orientation/pitch-deg" and "orientation/roll-deg"
#
#     It must be ensured that the direction of the lightbeam remains stable in relation
#     to the "world" (level 1).
#
#     In order to achieve this, the original direction of the light beam needs to be saved
#     at initialization time.
#
#     Stabilization is then achieved by the following steps:
#       - get current orientation of heli
#       - calculate difference in heading, pitch and roll
#       - calculate required heading and elevation of searchlight (sl) (relative to aircraft)
#         which is necessary to align the lightbeam to original orientation
#       - limit sl heading/elevation according to defined max/min movements
#       - interpolate sl heading/elevation from old to new values
#       - save new orientation
#
#     Remarks:
#       - if gimbal limits prohibit full correction of the sl orientation it will remain
#         at the extreme position until movement is possible again
#       - the actual heading/elevation relative to the heli is controlled by the operator
#         --> manual control must win over stabi
#         Remark: in order to achieve that, it seems to be necessary to pause stabi during
#                 manual movement to prevent "fighting" animations
#       - reset of sl will result in a new orientation of the lightbeam as predefined
#          - save orientation
#          - pause stabi
#          - interpolate to default heading/elevation
#          - activate stabi again
#
#     Movements and dependencies:
#
#           YAW/HEADING:
#           Model heading influence (delta-head-m) on searchlight heading (head-sl):
#
#                     equal over range except at 90 deg
#                     at elev-sl = 90 deg heading doesn't matter/is invalid
#
#             delta-head-sl = delta-head-m
#
#             Yaw of model is equal to heading change of searchlight.
#             Yaw of model has no influence on searchlight elevation !
#
#
#           PITCH:
#           Model pitch influence (delta-pitch-m) on searchlight elevation (elev-sl):
#
#                    max ... at head-sl = 0/180
#                    0   ... at head-sl = 90/270 deg
#
#             delta-elev-sl = delta-pitch-m * cos(head-sl)
#
#             Pitch of model has no influence on searchlight heading !
#
#
#           ROLL:
#           Model roll influence (delta-roll-m) on searchlight elevation (elev-sl):
#
#                    0   ... at head-sl = 0/180
#                    max ... at head-sl = 90/270 deg
#
#             delta-elev-sl = delta-roll-m * sin(head-sl)
#
#             Roll of model has no influence on searchlight heading !
#
#
#     Solution:
#     As the stabilzed movement of the searchlight requires sophisticated calculations,
#     the correction is not directly calculated in the animation. A Nasal script is used
#     instead.
#
#     Remark:
#     The stabilization is active when searchlight is active and switched off during pause.
#     Searchlight movement is limited by gimbal limitations.
#
#  Properties:
#
#    Model:
#
#     - orientation/heading-deg   ... + right, - left
#     - orientation/pitch-deg     ... + up, - down
#     - orientation/roll-deg      ... + right, - left
#
#    Searchlight:
#
#     - sim/model/searchlight/heading-deg     ... + left, - right
#     - sim/model/searchlight/elevation-deg   ... + up, - down
#
#     - sim/model/searchlight/orientation/heading-deg
#     - sim/model/searchlight/orientation/pitch-deg
#     - sim/model/searchlight/orientation/roll-deg
#
var stabilize_props = func {

  if ( getprop("/sim/model/ec130/searchlight_a800")   and
       getprop("/sim/model/searchlight/active")       and
       getprop("controls/electric/engine/generator") and
       !getprop("/sim/model/searchlight/paused")      and
       getprop("/sim/model/searchlight/stabi-active")     ) {

    # model orientation
    var head_m = getprop("orientation/heading-deg");
    var pitch_m = getprop("orientation/pitch-deg");
    var roll_m = getprop("orientation/roll-deg");

    # searchlight orientation reference
    var head_curr  = getprop("/sim/model/searchlight/orientation/heading-deg");
    var pitch_curr = getprop("/sim/model/searchlight/orientation/pitch-deg");
    var roll_curr  = getprop("/sim/model/searchlight/orientation/roll-deg");

    # searchlight orientation difference
    var head_diff  = head_m - head_curr;
    var pitch_diff = pitch_m - pitch_curr;
    var roll_diff  = roll_m - roll_curr;

    # save new orientation reference
    setprop("/sim/model/searchlight/orientation/heading-deg", head_m);
    setprop("/sim/model/searchlight/orientation/pitch-deg", pitch_m);
    setprop("/sim/model/searchlight/orientation/roll-deg", roll_m);

    # searchlight orientation (relative to heli)
    var head_sl = getprop("/sim/model/searchlight/heading-deg");
    var elev_sl = getprop("/sim/model/searchlight/elevation-deg");

    # heading_delta
    var head_delta = head_diff;

    # elevation_delta
    var elev_delta = (pitch_diff * math.cos(head_sl*0.01745329) * -1.0) - roll_diff * math.sin(head_sl*0.01745329);

    #
    # problem: head_sl, elev_sl needs to be limited
    #
    # solution:
    #  - calculate it's theoretical value
    #  - limit it
    #  - set stabilized value with limited value
    #

    # stabilized heading
    var h = head_sl + head_delta;
    if ( h > 360 ) { h = h - 360; }
    if ( h <   0 ) { h = h + 360; }

    # stabilized elevation
    var e = elev_sl - elev_delta;

    # limit movement and set props
    slight_limiter(h,e,1,1);

  }

  # loop
  settimer(stabilize_props, 0.05);

}
