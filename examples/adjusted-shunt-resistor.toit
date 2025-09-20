/* Use Case: Changing the scale of currents measured

If the task is to measure tiny standby or sleep currents (in the milliamp range) the default shunt resistor could be replaced with a larger value resistor (e.g. 1.0 Ω).  This increases the voltage drop per milliamp, giving the INA226 finer resolution for small loads.  The consequence is that the maximum measurable current shrinks to about 80 mA (since the INA226 input saturates at ~81.92 mV), and more power is dissipated in the shunt as heat.

Specifically: using the INA226’s shunt measurement specs:
- Shunt voltage LSB = 2.5 µV
- Shunt voltage max = ±81.92 mV

Shunt Resistor (SR) | Max Measurable Current | SR Wattage Reqt  | Resolution per bit | Note:
1.000 Ohm	        | 81.92 mA               |                  | 2.5 uA/bit         | Very fine resolution, only good for small currents (<0.1 A). 1/8 W Resistor is ample.
0.100 Ohm (default) | 0.8192 A               |                  | 25 uA/bit          | Middle ground; good for sub-amp measurements. A 0.125 W or 0.25 W Resistor is fine.
0.050 Ohm           | 1.6384 A               |                  | 50 uA/bit          | Wider range; 0.25 W resistor recommended (or higher for margin).
0.010 Ohm           | 8.192 A                |                  | 250 uA/bit         | High range but coarser steps. Use ≥1 W shunt - mind heating & layout.

*/

import gpio
import i2c
import ina226 show *

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device := bus.device DEFAULT_I2C_ADDRESS
  ina226-driver := Ina226 ina226-device

  ina226-driver.shunt-resistor --resistor=0.010                  // Reconfigure to the new 0.010 Ohm resistor
  ina226-driver.measure-mode --mode=INA226-MODE-CONTINUOUS       // Is the default, but setting again in case of consecutive tests
  
  // Continuously read and display values, in one row:
  10.repeat:
    print "$(%0.1f (ina226-driver.load-current --microamps))ua  $(%0.3f (ina226-driver.supply-voltage --volts))v  $(%0.1f (ina226-driver.load-power --milliwatts))mw"
    sleep --ms=500
