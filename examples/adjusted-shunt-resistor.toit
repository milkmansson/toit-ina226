/* Use Case: Measuring Very Small Currents

In this case the task is to measure tiny standby or sleep currents in the milliamp
range.  The default shunt resistor is replaced with a larger value resistor (e.g. 1.0 Ω).
This increases the voltage drop per milliamp, giving the INA226 finer resolution for small
loads. [The trade-off is that the maximum measurable current shrinks to about 80 mA (since
the INA226 input saturates at ~81.92 mV), and more power is dissipated in the shunt as heat.] */

import gpio
import i2c
import ina226

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226device := bus.device ina226.DEFAULT_I2C_ADDRESS
  ina226driver := ina226.Driver ina226device

  # Reconfigure to the new 1.0 Ohm resistor
  resistor-range --resistor=1.0
  
  # Continuously read and display values
  while true:
    print "$(%0.3f (ina226driver.load-current --amps))a"
    print "$(%0.2f (ina226driver.supply-voltage --volts))v"
    print "$(%0.4f (ina226driver.load-power --watts))w"
    sleep --ms=500
