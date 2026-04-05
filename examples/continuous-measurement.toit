// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *

/**
Simple continuous measurements example.

Simplest use case assumes an unmodified module with default wiring guidelines
 followed.  (Please see the Readme for pointers & guidance.) This example
 assumes:
- Module shunt resistor value R100 (0.1 Ohm) - Sample size of 1 (eg,
 no averaging) - Conversion time of 1100us
- Continuous Mode - Default wiring and default module shunt (see docs.)
*/

main:
  frequency := 400_000
  sda := gpio.Pin 19
  scl := gpio.Pin 20
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device := bus.device Ina226.I2C_ADDRESS
  ina226-driver := Ina226 ina226-device

  // Is the default, but setting in case of consecutive tests without reset.
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS
  // Wait for first registers to be ready (eg enough samples).
  ina226-driver.trigger-measurement --wait

  // Continuously read and display values.
  shunt-current-ma/float := 0.0
  supply-voltage-v/float := 0.0
  load-power-mw/float := 0.0
  10.repeat:
    10.repeat:
      shunt-current-ma = ina226-driver.read-shunt-current * 1000.0
      supply-voltage-v = ina226-driver.read-supply-voltage
      load-power-mw = ina226-driver.read-load-power * 1000.0
      print "Measurement $(%02d it): $(%0.1f shunt-current-ma)ma  $(%0.3f supply-voltage-v)v  $(%0.2f load-power-mw)mw"
      sleep --ms=500

    print "Waiting 30 seconds..."
    print
    sleep (Duration --s=30)
