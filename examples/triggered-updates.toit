// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *

/**
Triggered Updates Example:

This use case is relevant where a balance is required between Update Speed and
 Accuracy - eg in a Battery-Powered Scenario.  The INA226 is used to monitor the
 node’s power draw to be able to estimate battery life.  Instead of running in
 continuous conversion mode use triggered (single-shot) mode with longer
 conversion times and averaging enabled.
*/

main:
  frequency := 400_000
  sda   := gpio.Pin 26
  scl   := gpio.Pin 25
  bus   := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  event := 0

  ina226-device := bus.device Ina226.I2C_ADDRESS
  ina226-driver := Ina226 ina226-device --shunt-resistor=0.100

  // Set sample size to 1 to help show variation in voltage is noticable.
  ina226-driver.set-sampling-rate Ina226.AVERAGE-1-SAMPLE
  ina226-driver.set-bus-conversion-time Ina226.TIMING-204-US
  ina226-driver.set-shunt-conversion-time Ina226.TIMING-204-US

  // Read and display values every minute, but turn the device off in between.
  10.repeat:
    // Three CONTINUOUS measurements, fluctuation expected
    ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS
    ina226-driver.set-power-on
    print "Three CONTINUOUS measurements, fluctuation usually expected"
    3.repeat:
      print "      READ $(%02d it): $(%0.2f (ina226-driver.read-shunt-current * 1000.0))ma  $(%0.4f (ina226-driver.read-supply-voltage))v  $(%0.1f (ina226-driver.read-load-power * 1000.0))mw"
      sleep --ms=500

    // CHANGE MODE - trigger a measurement and switch off
    ina226-driver.set-measure-mode Ina226.MODE-TRIGGERED

    3.repeat:
      ina226-driver.set-power-on
      ina226-driver.trigger-measurement
      ina226-driver.set-power-off
      event = it
      print " TRIGGER EVENT #$(%02d event) - Registers read 3 times (new values, but no change between reads)"

      3.repeat:
        print "  #$(%02d event) READ $(%02d it): $(%0.2f (ina226-driver.read-shunt-current * 1000.0))ma  $(%0.3f (ina226-driver.read-supply-voltage))v  $(%0.1f (ina226-driver.read-load-power * 1000.0))mw"
        sleep --ms=500

    print "Waiting 30 seconds"
    print ""
    sleep (Duration --s=30)
