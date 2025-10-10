// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *

/*
Use Case: Changing the scale of currents measured

If the task is to measure tiny standby or sleep currents (in the milliamp range) the default
shunt resistor could be replaced with a larger value resistor (e.g. 1.0 ΩOhm).  This increases
the voltage drop per milliamp, giving the INA226 finer resolution for small loads.  The
consequence is that the maximum measurable current shrinks to about 80 mA (since the INA226
input saturates at appx 81.92 mV), and more power is dissipated in the shunt as heat.

Please see the README.md for example Shunt Resistor values.
*/

main:
  // Adjust these to pin numbers in your setup.
  sda := gpio.Pin 19
  scl := gpio.Pin 20

  frequency := 400_000
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  ina226-device := bus.device Ina226.I2C_ADDRESS

  // Creates instance using an 0.010 Ohm shunt resistor
  ina226-driver := Ina226 ina226-device --shunt-resistor=0.010
  // Is the default, but setting again in case of consecutive tests without reset
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS

  // Continuously read and display values, in one row:
  shunt-current/float := 0.0
  bus-voltage/float   := 0.0
  load-power/float    := 0.0
  10.repeat:
    shunt-current = ina226-driver.read-shunt-current * 1000.0 * 1000.0
    bus-voltage = ina226-driver.read-bus-voltage
    load-power = ina226-driver.read-load-power * 1000
    print "$(%0.1f shunt-current)ua  $(%0.3f bus-voltage)v  $(%0.1f load-power)mw"
    sleep --ms=500
