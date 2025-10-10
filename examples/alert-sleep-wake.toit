// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import i2c
import ina226 show *
import esp32
import system

EXAMPLE-STAGE-1 ::= 0x1
EXAMPLE-STAGE-2 ::= 0x2
EXAMPLE-MEASUREMENTS ::= 10
/**
# Example: Alert-wake - An alert on the INA226 waking the ESP32 from deep sleep.

## Task: Create a circuit that runs normally, and allws the ESP32 to be in deep
sleep. Establish a scenario to create an alert the INA226, which sends an alert
on it's alert pin.  This pin would be tied to a PIN on the ESP32 set to wake it
from deep sleep.

There are potentially many ways to do this, including some that could be
  automatic and not involve any hardware.  However, to make it real, in this
  example we will use:
  - Momentary pushbutton.
  - Diode (xxx) - this has approx xxxV voltage loss when in use.
  - Load - We will use a small length of WS2812B LED strip, however other loads
    can also be ok.
  - This example could be made more elaborate, for example, using an SSD1306 to
    show the current state, or indicate that the ESP32 has woken up.

## Steps:
  1. Construct load/and momentary switch diversion to include diode
  2. STAGE 1: Run the load and Use the INA226 to find 'normal' voltage/current.
  3. STAGE 2: Configure values in the code, and run again with limits.  Device
     will wake at the button press, show information about the alert, and go
     back to deep sleep after a short time.

## Wiring:
In this example, we will:
  - Tie the INA226 Alert Pin to the GPIO specified in $ESP-ALERT-PIN.
  - This tie needs a 10KOhm pull up - connect the resistor between the tie, and
    the +3.3v rail.

Note that the load and vbus pins for the INA226 should not be the 3v3 rail that
is used to power the I2C devices.  In this example, the load is on the 5v rail
only - we don't want the button to cause malfunctions of the INA226.  In this
example the alert pin is configured to go low, meaning that removing the INA226
would also constitute a trigger.

## Code:
In the code below, just comment out one of the two statics to indicate
which stage is intended.  In this code, stable values are preferred so higher
averages and longer convergence times have been opted for.  Note also that the
alert pin will go low when alerting, and the ESP32 wake pin instruction also
reflects this.

*/

/** STAGE1: Uncomment the lines below, and comment out STAGE2: */
CURRENT-STAGE := EXAMPLE-STAGE-1

/** STAGE2: Uncomment the lines below and place the measurements in the variables
indicated. Comment out STAGE1 lines above. */
// CURRENT-STAGE := EXAMPLE-STAGE-2
EXAMPLE-STAGE-2-ALERT-VOLTAGE-UNDER := 0.000
ESP-ALERT-PIN ::= 13
ESP-SLEEP-LIMIT ::= Duration --m=10

/** Main code: */
main:
  // Checking device is present and the platform supports wake from pin
  if system.architecture == "esp32s3":
    print "  Device is ($system.architecture). Pin based 'enable-external-wakeup' not supported on this architecture."
    print "  Cannot continue."
    return

  plain-total-current := 0.0
  plain-total-voltage := 0.0
  sag-total-current := 0.0
  sag-total-voltage := 0.0
  this-current := 0.0
  this-voltage := 0.0

  frequency := 400_000
  sda := gpio.Pin 26
  scl := gpio.Pin 25
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  scandevices := bus.scan

  if not scandevices.contains Ina226.I2C_ADDRESS:
    print "No ina226 device found.  Stopping."
    return
  ina226-device := bus.device Ina226.I2C_ADDRESS
  ina226-driver := Ina226 ina226-device

  // Set initial state and enable continuous measurements.
  ina226-driver.set-measure-mode Ina226.MODE-CONTINUOUS

  // Set reasonable averaging to ensure as stable measurements as possible.
  ina226-driver.set-sampling-rate Ina226.AVERAGE-1024-SAMPLES
  ina226-driver.set-bus-conversion-time Ina226.TIMING-1100-US
  ina226-driver.set-shunt-conversion-time Ina226.TIMING-1100-US
  ina226-driver.clear-alert

  // Set alert latching - Note that Alert Pin is 'active low' by default.
  ina226-driver.set-alert-latching 1

  // Take action based on current stage:
  if (CURRENT-STAGE == EXAMPLE-STAGE-1) and (esp32.reset-reason != esp32.RESET-DEEPSLEEP):
    print
    print " Original State: showing $(EXAMPLE-MEASUREMENTS) measurements:"
    EXAMPLE-MEASUREMENTS.repeat:
      ina226-driver.trigger-measurement --wait
      this-voltage = ina226-driver.read-bus-voltage
      this-current = ina226-driver.read-shunt-current
      print "\tMeasurement $(%02d it + 1): $(%0.3f this-voltage)v $(%0.3f this-current)a"
      plain-total-current += this-current
      plain-total-voltage += this-voltage
    print
    print " Waiting 3 seconds.  Press and hold the button for the next $(EXAMPLE-MEASUREMENTS) Measurements."
    print " See that the values change in the results:"
    sleep --ms=3000
    EXAMPLE-MEASUREMENTS.repeat:
      ina226-driver.trigger-measurement --wait
      this-voltage = ina226-driver.read-bus-voltage
      this-current = ina226-driver.read-shunt-current
      print "\tMeasurement $(%02d it + 1): $(%0.3f this-voltage)v $(%0.3f this-current)a"
      sag-total-current += this-current
      sag-total-voltage += this-voltage

    print
    print " If using the suggested load and code, use the following values to guide STAGE 2 configuration:"
    plain-volts-average := plain-total-voltage / EXAMPLE-MEASUREMENTS
    plain-current-average := plain-total-current / EXAMPLE-MEASUREMENTS
    sag-volts-average := plain-total-voltage / EXAMPLE-MEASUREMENTS
    sag-current-average := plain-total-current / EXAMPLE-MEASUREMENTS
    print " \tAverage without button        : $(%0.3f plain-volts-average)v $(%0.3f plain-current-average)a"
    print " \tAverage *with* button pushed  : $(%0.3f sag-volts-average)v $(%0.3f sag-current-average)a"
    print
    print

  else if CURRENT-STAGE == EXAMPLE-STAGE-2:
    if esp32.reset-reason == esp32.RESET-DEEPSLEEP:
      print
      sleep-duration := Duration --ms=esp32.total-deep-sleep-time
      print " WOKEN FROM SLEEP after $(sleep-duration.in-s) !!"
      if esp32.wakeup-cause == esp32.WAKEUP-EXT1: print " REASON: Woken by pin $(ESP-ALERT-PIN)"
      if esp32.wakeup-cause == esp32.WAKEUP-TIMER: print " REASON: Woken by timer $(ESP-SLEEP-LIMIT.in-m)min"
      // Strictly speaking these are not useful for this exact example, but are
      // included to help learn about deep sleep and wakeup reasons.
      if esp32.wakeup-cause == esp32.WAKEUP-EXT0: print " REASON: Woken by [WAKEUP-EXT0]"
      if esp32.wakeup-cause == esp32.WAKEUP-GPIO: print " REASON: Woken by [WAKEUP-GPIO]"
      if esp32.wakeup-cause == esp32.WAKEUP-TOUCHPAD: print " REASON: Woken by [WAKEUP-TOUCHPAD]"
      if esp32.wakeup-cause == esp32.WAKEUP-UART: print " REASON: Woken by [WAKEUP-UART]"
      if esp32.wakeup-cause == esp32.WAKEUP-ULP: print " REASON: Woken by [WAKEUP-ULP]"
      if esp32.wakeup-cause == esp32.WAKEUP-UNDEFINED: print " REASON: Woken by [WAKEUP-UNDEFINED]"

      print
      sleep --ms=3000
      print " Getting ready to repeat deep-sleep/wake cycle again."
      print
    else:
      // Reset reason was something else - we don't care at this point.


    // Show current measurements for interest, and to take a little time up:
    EXAMPLE-MEASUREMENTS.repeat:
      ina226-driver.trigger-measurement --wait
      this-voltage = ina226-driver.read-bus-voltage
      this-current = ina226-driver.read-shunt-current
      print "\tMeasurement $(%02d it + 1): $(%0.3f this-voltage)v $(%0.3f this-current)a"

    // Show steps and warn before sleep:
    print " Setting bus under voltage alert to: $(%0.3f EXAMPLE-STAGE-2-ALERT-VOLTAGE-UNDER)"
    ina226-driver.set-bus-over-voltage-alert EXAMPLE-STAGE-2-ALERT-VOLTAGE-UNDER
    ina226-driver.clear-alert
    print " Setting Alert Pin..."
    esp32.enable-external-wakeup ESP-ALERT-PIN false
    print " Going to deep sleep (for $(ESP-SLEEP-LIMIT.in-m)mins) in 5 seconds..."
    sleep --ms=5000
    print " Deep sleep now..."
    print
    esp32.deep-sleep ESP-SLEEP-LIMIT

  else:
    print "Unexpected STAGE value $(CURRENT-STAGE), RESET reason $(esp32.reset-reason), or other error. Stopping."
    return
