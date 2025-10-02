// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *

/* Use Case: Changing the scale of currents measured

If the task is to measure tiny standby or sleep currents (in the milliamp range) the default
shunt resistor could be replaced with a larger value resistor (e.g. 1.0 ΩOhm).  This increases
the voltage drop per milliamp, giving the INA226 finer resolution for small loads.  The
consequence is that the maximum measurable current shrinks to about 80 mA (since the INA226
input saturates at appx 81.92 mV), and more power is dissipated in the shunt as heat.

Specifically: using the INA226’s shunt measurement specs:
- Shunt voltage LSB = 2.5 uV
- Shunt voltage max = ±81.92 mV

Shunt Resistor (SR) | Max Measurable Current | Shunt Resistor   | Resolution per bit | Note:
                    |                        | Wattage Reqt     |                    |
--------------------|------------------------|------------------|--------------------|------------------------------------------
1.000 Ohm	    | 81.92 mA               | 0.125w (min)     | 2.5 uA/bit         | Very fine resolution, only good for small
                    |                        |                  |                    | currents (<0.1 A).
--------------------|------------------------|------------------|--------------------|------------------------------------------
0.100 Ohm (default) | 0.8192 A               | 0.125 W (min)    | 25 uA/bit          | Middle ground; good for sub-amp
                    |                        | 0.25 W (safe)    |                    | measurements.
--------------------|------------------------|------------------|--------------------|------------------------------------------
0.050 Ohm           | 1.6384 A               | 0.25 W (min)     | 50 uA/bit          | Wider range; 0.25 W resistor recommended,
                    |                        | 0.5 W (safe)     |                    | or higher for margin.
--------------------|------------------------|------------------|--------------------|------------------------------------------
0.010 Ohm           | 8.192 A                | 1 W (min)        | 250 uA/bit         | High range but coarser steps. Use ≥1 W
                    |                        | 2 W (preferred)  |                    | shunt - mind heating & layout.
--------------------|------------------------|------------------|--------------------|------------------------------------------
*/

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device := bus.device Ina226.I2C_ADDRESS

  // Creates instance using an 0.010 Ohm shunt resistor
  ina226-driver := Ina226 ina226-device --shunt-resistor=0.010
  // Is the default, but setting again in case of consecutive tests without reset
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS

  // Continuously read and display values, in one row:
  shunt-current-ua/float := 0.0
  bus-voltage/float      := 0.0
  load-power-mw/float    := 0.0
  10.repeat:
    shunt-current-ua = ina226-driver.read-shunt-current * 1000.0 * 1000.0
    bus-voltage = ina226-driver.read-bus-voltage
    load-power-mw = ina226-driver.read-load-power * 1000
    print "$(%0.1f shunt-current-ua)ua  $(%0.3f bus-voltage)v  $(%0.1f load-power-mw)mw"
    sleep --ms=500
