
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ..src.ina226 show *


/** 
Tests: Alerts

**Test Process:**
For two tests:
1. set initial state and enable channels
2. take a measurement to start with
3. iterate 10 steps (5 either side of the actual measurement) set the alert to the step 
4. for each iteration check if the alarm went off

*/

SHUNT-CURRENT-MAX  := 1.638 //amps   // theroetical maximum, not practical

ina226-device            := ?
ina226-driver            := ?

main:
  frequency      := 400_000
  sda            := gpio.Pin 26
  scl            := gpio.Pin 25
  bus            := i2c.Bus --sda=sda --scl=scl --frequency=frequency

  ina226-device = bus.device Ina226.I2C_ADDRESS
  ina226-driver = Ina226 ina226-device

  test-result/string          := ""
  test-target/float           := 0.0
  current-test-value/float    := 0.0

  // set initial state and enable channels
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS
  ina226-driver.set-shunt-resistor 0.100                                    // Ensure set to default 0.100 shunt resistor
  ina226-driver.set-power-on                                                // Setting these in case different tests are run consecutively

  // set reasonable average to ensure stable measurements 
  ina226-driver.set-sampling-rate Ina226.AVERAGE-16-SAMPLES
  ina226-driver.set-bus-conversion-time Ina226.TIMING-1100-US
  ina226-driver.set-shunt-conversion-time Ina226.TIMING-1100-US
  ina226-driver.clear-alert
  ina226-driver.enable-alert-latch 

  // show current state (in case the test needs adjusting
  print " Original State: $(show-current-state)"         //repeat is zero based
  print ""

  // get the current value and set target alert limit at +10%
  ina226-driver.trigger-measurement --wait=true
  test-target = ina226-driver.read-bus-voltage

  10.repeat:
    ina226-driver.clear-alert
    current-test-value = (test-target / 5 * it)
    ina226-driver.set-bus-over-voltage-alert current-test-value
    sleep --ms=ina226-driver.get-estimated-conversion-time-ms
    test-result = "$((ina226-driver.alert-limit == true) ? "ALERT" : "NORMAL")"
    print " Test #$(it): $(show-current-state) - BUS-OVER-VOLT-ALERT: limit=$(%0.4f current-test-value) result = $(test-result)"  
  print ""


  // get the current value and set target alert limit at +10%
  ina226-driver.trigger-measurement --wait=true
  test-target = ina226-driver.read-shunt-current

  10.repeat:
    ina226-driver.clear-alert
    current-test-value = test-target / 5 * it
    if current-test-value < 0.0 : current-test-value = 0.0
    ina226-driver.set-shunt-over-current-alert current-test-value
    sleep --ms=ina226-driver.get-estimated-conversion-time-ms
    test-result = "$((ina226-driver.alert-limit == true) ? "ALERT" : "NORMAL")"
    print " Test #$(it): $(show-current-state) - SHUNT-CURRENT-OVER-ALERT: limit=$(%0.6f current-test-value) result = $(test-result)"  
  print ""


show-current-state -> string:
  shunt-current-a/float  := ina226-driver.read-shunt-current                    // a
  shunt-voltage-mv/float := ina226-driver.read-shunt-voltage * 1000             // mv
  bus-voltage-v/float    := ina226-driver.read-bus-voltage                      // v
  load-power-mw/float    := ina226-driver.read-load-power * 1000.0              // mw
  return "Shunt: $(%0.6f shunt-current-a)a  $(%0.3f shunt-voltage-mv)mv  Bus: $(%0.3f bus-voltage-v)v  Power: $(%0.1f load-power-mw)mw"
