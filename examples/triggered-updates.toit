
import gpio
import i2c
import ..src.ina226 show *

/**
Triggered Updates Example:

This use case is relevant where a balance is required between Update Speed and Accuracy -
eg in a Battery-Powered Scenario.  The INA226 is used to monitor the node’s power draw
to be able to estimate battery life.  The driver runs in continuous conversion mode by
default, sampling all the time at relatively short conversion times.  This has a higher
power requirement as the INA226 is constantly awake and operating. In this case the 
driver needs to use triggered (single-shot) mode with longer conversion times and
averaging enabled.
*/

main:
  frequency := 400_000
  sda   := gpio.Pin 26
  scl   := gpio.Pin 25
  bus   := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  event := 0

  ina226-device := bus.device Ina226.I2C_ADDRESS
  ina226-driver := Ina226 ina226-device

  // Set sample size to 1 to help show variation in voltage is noticable
  ina226-driver.set-sampling-rate --rate=Ina226.AVERAGE-1-SAMPLE
  ina226-driver.set-conversion-time --bus=Ina226.TIMING-204-US
  ina226-driver.set-conversion-time --shunt=Ina226.TIMING-204-US
  ina226-driver.set-shunt-resistor --resistor=0.100
  
  // Read and display values every minute, but turn the device off in between
  10.repeat:
    // Three CONTINUOUS measurements, fluctuation expected
    ina226-driver.set-measure-mode --mode=Ina226.MODE-CONTINUOUS
    ina226-driver.set-power-on
    print "Three CONTINUOUS measurements, fluctuation usually expected"
    3.repeat:
      print "      READ $(%02d it): $(%0.2f (ina226-driver.read-shunt-current * 1000.0))ma  $(%0.4f (ina226-driver.read-supply-voltage))v  $(%0.1f (ina226-driver.read-load-power * 1000.0))mw"
      sleep --ms=500
    
    // CHANGE MODE - trigger a measurement and switch off
    ina226-driver.set-measure-mode --mode=Ina226.MODE-TRIGGERED

    3.repeat:
      ina226-driver.set-power-on
      ina226-driver.trigger-single-measurement
      ina226-driver.set-power-off
      event = it
      print " TRIGGER EVENT #$(%02d event) - Registers read 3 times (new values, but no change between reads)"

      3.repeat:
        print "  #$(%02d event) READ $(%02d it): $(%0.2f (ina226-driver.read-shunt-current * 1000.0))ma  $(%0.3f (ina226-driver.read-supply-voltage))v  $(%0.1f (ina226-driver.read-load-power * 1000.0))mw"
        sleep --ms=500

    print "Waiting 30 seconds"
    print ""
    sleep (Duration --s=30)
