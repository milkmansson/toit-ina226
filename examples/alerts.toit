// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *


/**
Example: Alerts

**Process:**
Demonstrates two Alert examples using the following logic, for each of
'bus-voltage-alert' and `shunt-voltage-alert`:
1. set initial state and enable channels
2. take a measurement to start with
3. set the alert using the current measurement
3. iterate 10 steps (5 either side of the actual measurement) set the alert to
the step
4. for each iteration check the alarm went off

*/

SHUNT-CURRENT-MAX ::= 1.638 //amps   // Theroetical maximum, not practical.

main:
  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device := bus.device Ina226.I2C_ADDRESS
  ina226-driver := Ina226 ina226-device
  test-result/string := ""
  test-target/float := 0.0
  current-test-value/float := 0.0

  // Set initial state and enable channels.
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS
  // Setting these in case several different tests are run consecutively.
  ina226-driver.set-power-on

  // Set reasonable average to ensure stable measurements.
  ina226-driver.set-sampling-rate Ina226.AVERAGE-16-SAMPLES
  ina226-driver.set-bus-conversion-time Ina226.TIMING-1100-US
  ina226-driver.set-shunt-conversion-time Ina226.TIMING-1100-US
  ina226-driver.clear-alert
  ina226-driver.set-alert-latching 1

  // Show current state (in case the test needs adjusting.
  print " Original State: $(current-state-as-string ina226-driver)"
  print

  // Get the current value and set target alert limit at +10%.
  ina226-driver.trigger-measurement --wait
  test-target = ina226-driver.read-bus-voltage

  10.repeat:
    ina226-driver.clear-alert
    current-test-value = test-target / 5 * it
    ina226-driver.set-bus-over-voltage-alert current-test-value
    sleep --ms=ina226-driver.get-estimated-conversion-time-ms
    test-result = ina226-driver.alert-limit == true ? "ALERT" : "NORMAL"
    print " Test #$it: $(current-state-as-string ina226-driver) - BUS-OVER-VOLT-ALERT: limit=$(%0.4f current-test-value) result = $(test-result)"
  print


  // Get the current value and then set target alert limit for each iteration
  // to show the alert triggering once past the current measurement.
  ina226-driver.trigger-measurement --wait
  test-target = ina226-driver.read-shunt-current

  10.repeat:
    ina226-driver.clear-alert
    current-test-value = test-target / 5 * it
    if current-test-value < 0.0 : current-test-value = 0.0
    ina226-driver.set-shunt-over-current-alert current-test-value
    sleep --ms=ina226-driver.get-estimated-conversion-time-ms
    test-result = "$((ina226-driver.alert-limit == true) ? "ALERT" : "NORMAL")"
    print " Test #$(it): $(current-state-as-string ina226-driver) - SHUNT-CURRENT-OVER-ALERT: limit=$(%0.6f current-test-value) result = $(test-result)"
  print


current-state-as-string driver -> string:
  shunt-current-a/float  := driver.read-shunt-current
  shunt-voltage-mv/float := driver.read-shunt-voltage * 1000
  bus-voltage-v/float    := driver.read-bus-voltage
  load-power-mw/float    := driver.read-load-power * 1000.0
  return "Shunt: $(%0.6f shunt-current-a)a  $(%0.3f shunt-voltage-mv)mv  Bus: $(%0.3f bus-voltage-v)v  Power: $(%0.1f load-power-mw)mw"
