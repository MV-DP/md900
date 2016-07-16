 #disable cas when engines running- otherwise we are overflooded with error messages in the console
 call_casdisable = func {

 if ( getprop("/rotors/main/rpm")> 80.0)

   
	 
	 {
	  
	  setprop("/controls/flight/fcs/cas-enabled", 0);
	 	  
	  
	  } else {

            setprop("/controls/flight/fcs/cas-enabled", 1.0);

           
          }
	  
 #if (RUN2 ==1) {
	  
	#  setprop("/controls/flight/fcs/cas-enabled", 0);
	  
	#  } else {

         #   setprop("/controls/flight/fcs/cas-enabled", 1.0);

           
        #  }


settimer(call_casdisable, 0.2);   

}

 

init = func {

   settimer(call_casdisable, 0.0);

}



init();
	  


         

        