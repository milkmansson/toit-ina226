import gpio
import i2c
import ina226

# Assumes default wiring and default module shunt 
# resistor value of R100 (0.100 Ohm)

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226device := bus.device ina226.DEFAULT_I2C_ADDRESS
  ina226driver := ina226.Driver ina226device

  # Wait for first registers to be ready
  single-measurement
  
  # Continuously read and display values
  while true:
    print "$(%0.3f (ina226driver.load-current --amps))a"
    print "$(%0.2f (ina226driver.supply-voltage --volts))v"
    print "$(%0.4f (ina226driver.load-power --watts))w"
    sleep --ms=50