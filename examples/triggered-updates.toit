/* Use Case 3: Balancing Update Speed vs. Accuracy in a Battery-Powered Scenario
Where the module must be wired into a solution running on a battery. The INA226 is used to monitor the node’s power draw to be able to estimate battery life.  The driver runs in continuous conversion mode by default, sampling all the time at relatively short conversion times.  This has a higher power requirement as the INA226 is constantly awake and operating.  
In this case the driver needs to use triggered (single-shot) mode with longer conversion times and averaging enabled. */

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

  ina226driver.sampling-rate --rate=AVERAGE-256-SAMPLES
  ina226driver.conversion-time --time=TIMING-204-US
  ina226driver.measure-mode --mode=MODE-TRIGGERED

  
  # Read and display values every minute, but turn the device off in between
  while true:
    ina226driver.power-up
    single-measurement
    print "$(%0.3f (ina226driver.load-current --amps))a"
    print "$(%0.2f (ina226driver.supply-voltage --volts))v"
    print "$(%0.4f (ina226driver.load-power --watts))w"
    ina226driver.power-off
    sleep --ms=60000 // Wait 1 Minute