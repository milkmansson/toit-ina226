/** Simple Continuous Measurements:
Simplest use case assumes an unmodified module with default wiring guidelines followed.  (Please see the Readme for pointers & guidance.) Assumes:
 - Module shunt resistor value R100 (0.1 Ohm)
 - Sample size of 1 (eg, no averaging)
 - Conversion time of 1100us
 - Continuous Mode

*/

import gpio
import i2c
import ina226 show *

// Assumes default wiring and default module shunt 
// resistor value of R100 (0.100 Ohm)

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device := bus.device DEFAULT_I2C_ADDRESS
  ina226-driver := Ina226 ina226-device

  ina226-driver.measure-mode --mode=INA226-MODE-CONTINUOUS       // Is the default, but setting again in case of consecutive tests
  ina226-driver.single-measurement                               // Wait for first registers to be ready (eg enough samples)
  
  // Continuously read and display values
  10.repeat:
    10.repeat:
      print "Measurement $(%02d it): $(%0.1f (ina226-driver.load-current --milliamps))ma  $(%0.3f (ina226-driver.supply-voltage --volts))v  $(%0.2f (ina226-driver.load-power --milliwatts))mw"
      sleep --ms=500

    print "Waiting 30 seconds"
    print ""
    sleep (Duration --s=30)
