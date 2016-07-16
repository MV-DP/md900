# MV-DP
# December 2015
# This file is licenced under the terms of the GNU General Public Licence V2 or later
# wiper action
setlistener("controls/electric/wipers/switch", func() {
  wiper_action();  
}, 0, 1);

var wiper_action = func(){

    var ws = getprop("controls/electric/wipers/switch") or 0;
    var d = getprop("/controls/special/wiper-deg") or 0;
