
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This file also includes derivative
// work from other authors and sources.  See accompanying documentation.

import log
import binary
import serial.device as serial
import serial.registers as registers

/** Toit Driver Library for an INA226 module, DC Shunt current and power sensor.

Several common modules exist based on the TI INA226 chip.  Datasheet:
 https://www.ti.com/lit/ds/symlink/ina226.pdf One example:
 https://esphome.io/components/sensor/ina226/.  There are others with different
 feature sets and may be partially code compatible.  - For all sensor reads,
 values are floats, and supplied in base SI units: volts, amps and watts.  -
 get-* and set-* methods/functions are used for setting properties about the
 class or the sensor itself.  - read-* methods/functions are used for getting
 reading actual sensor values

To use this library, consult the examples.
*/


class Ina226:
  /**
  Default $I2C-ADDRESS is 64 (0x40).  Valid addresses: 64 to 79.  See Datasheet.
  */
  static I2C-ADDRESS                            ::= 0x40

  /**
  MODE constants used while configuring $set-measure-mode.
  */
  static MODE-POWER-DOWN                       ::= 0b000
  static MODE-TRIGGERED                        ::= 0b011
  static MODE-CONTINUOUS                       ::= 0b111 // Class Default.

  /**
  Alert Types for alert functions.
  */
  static ALERT-ENABLE-SHUNT-OVER-VOLTAGE_      ::= 0b10000000_00000000
  static ALERT-ENABLE-SHUNT-UNDER-VOLTAGE_     ::= 0b01000000_00000000
  static ALERT-ENABLE-BUS-OVER-VOLTAGE_        ::= 0b00100000_00000000
  static ALERT-ENABLE-BUS-UNDER-VOLTAGE_       ::= 0b00010000_00000000
  static ALERT-ENABLE-POWER-OVER_              ::= 0b00001000_00000000
  static ALERT-ENABLE-CONVERSION-READY_        ::= 0b00000100_00000000
  static ALERT-PIN-POLARITY_                   ::= 0b00000000_00000010
  static ALERT-LATCH-ENABLE_                   ::= 0b00000000_00000001

  /**
  Actual Alert Flags
  */
  static FUNCTION-ALERT-FLAG_                  ::= 0b00000000_00010000
  static CONVERSION-READY-ALERT-FLAG_          ::= 0b00000000_00001000
  static MATH-OVERFLOW-ALERT-FLAG_             ::= 0b00000000_00000100

  /** Sampling option: (Default) - 1 sample = no averaging. */
  static AVERAGE-1-SAMPLE                      ::= 0x00
  /** Sampling option: Values averaged over 4 samples. */
  static AVERAGE-4-SAMPLES                     ::= 0x01
  /** Sampling option: Values averaged over 16 samples. */
  static AVERAGE-16-SAMPLES                    ::= 0x02
  /** Sampling option: Values averaged over 64 samples. */
  static AVERAGE-64-SAMPLES                    ::= 0x03
  /** Sampling option: Values averaged over 128 samples. */
  static AVERAGE-128-SAMPLES                   ::= 0x04
  /** Sampling option: Values averaged over 256 samples. */
  static AVERAGE-256-SAMPLES                   ::= 0x05
  /** Sampling option: Values averaged over 512 samples. */
  static AVERAGE-512-SAMPLES                   ::= 0x06
  /** Sampling option: Values averaged over 1024 samples. */
  static AVERAGE-1024-SAMPLES                  ::= 0x07

  /** Conversion time setting: 140us */
  static TIMING-140-US                         ::= 0x0000
  /** Conversion time setting: 204us */
  static TIMING-204-US                         ::= 0x0001
  /** Conversion time setting: 332us */
  static TIMING-332-US                         ::= 0x0002
  /** Conversion time setting: 588us */
  static TIMING-588-US                         ::= 0x0003
  /** Conversion time setting: 1100us (Default) */
  static TIMING-1100-US                        ::= 0x0004
  /** Conversion time setting: 2100us */
  static TIMING-2100-US                        ::= 0x0005
  /** Conversion time setting: 4200us */
  static TIMING-4200-US                        ::= 0x0006
  /** Conversion time setting: 8300us */
  static TIMING-8300-US                        ::= 0x0007

  // Core Register Addresses.
  static REGISTER-CONFIG_                      ::= 0x00  //RW  // All-register reset, shunt voltage and bus voltage ADC conversion times and averaging, operating mode.
  static REGISTER-SHUNT-VOLTAGE_               ::= 0x01  //R   // Shunt voltage measurement data.
  static REGISTER-BUS-VOLTAGE_                 ::= 0x02  //R   // Bus voltage measurement data.
  static REGISTER-LOAD-POWER_                  ::= 0x03  //R   // Value of the calculated power being delivered to the load.
  static REGISTER-SHUNT-CURRENT_               ::= 0x04  //R   // Value of the calculated current flowing through the shunt resistor.
  static REGISTER-CALIBRATION_                 ::= 0x05  //RW  // Sets full-scale range and LSB of current and power measurements. Overall system calibration.
  static REGISTER-MASK-ENABLE_                 ::= 0x06  //RW  // Alert configuration and Conversion Ready flag.
  static REGISTER-ALERT-LIMIT_                 ::= 0x07  //RW  // Limit value to compare to the selected Alert function.
  static REGISTER-MANUF-ID_                    ::= 0xFE  //R   // Contains unique manufacturer identification number.
  static REGISTER-DIE-ID_                      ::= 0xFF  //R   // Contains unique die identification number.

  // Die & Manufacturer Info Masks for REGISTER-DIE-ID_
  static DIE-ID-RID-MASK_                      ::= 0b00000000_00001111
  static DIE-ID-DID-MASK_                      ::= 0b11111111_11110000

  // Actual INA226 device ID - to identify this chip over INA3221 etc.
  static INA226-DEVICE-ID_                     ::= 0x0226

  // Configuration Register bitmasks.
  static CONF-RESET-MASK_                      ::= 0b10000000_00000000
  static CONF-AVERAGE-MASK_                    ::= 0b00001110_00000000
  static CONF-BUSVC-MASK_                      ::= 0b00000001_11000000
  static CONF-SHUNTVC-MASK_                    ::= 0b00000000_00111000
  static CONF-MODE-MASK_                       ::= 0b00000000_00000111

  static INTERNAL_SCALING_VALUE_/float         ::= 0.00512
  static SHUNT-FULL-SCALE-VOLTAGE-LIMIT_/float ::= 0.08192    // volts.
  static SHUNT-VOLTAGE-LSB_                    ::= 0.0000025  // volts. 2.5 µV/bit.
  static BUS-VOLTAGE-LSB_                      ::= 0.00125    // volts, 1.25 mV/bit

  // Private variables.
  reg_/registers.Registers := ?
  logger_/log.Logger := ?
  current-divider-ma_/float := 0.0
  power-multiplier-mw_/float := 0.0
  current-LSB_/float := 0.0
  shunt-resistor_/float := 0.0
  current-range_/float := 0.0
  max-current_/float := 0.0

  constructor
      dev/serial.Device
      --shunt-resistor/float=0.100
      --measure-mode=MODE-CONTINUOUS
      --logger/log.Logger=log.default:
    logger_ = logger.with-name "ina226"
    reg_ = dev.registers
    shunt-resistor_ = shunt-resistor
    set-measure-mode measure-mode

    dev-id := read-device-identification
    man-id := read-manufacturer-id
    dev-rev := read-device-revision

    if (dev-id != INA226-DEVICE-ID_):
      logger_.error "Device is NOT an INA226" --tags={ "expected-id" : INA226-DEVICE-ID_, "received-id": dev-id }
      throw "Device is not an INA226. Expected 0x$(%04x INA226-DEVICE-ID_) got 0x$(%04x dev-id)"

    // Maybe not required but the manual suggests it should be done.
    reset_

    // Initialize Default sampling, conversion timing, and measuring mode.
    set-sampling-rate AVERAGE-1-SAMPLE
    set-bus-conversion-time TIMING-1100-US
    set-shunt-conversion-time TIMING-1100-US

    // Performing a single measurement during initialisation assists with accuracy for first reads.
    trigger-measurement --wait

  /**
  Resets the device.
  */
  reset_ -> none:
    write-register_ REGISTER-CONFIG_ 0b1 --mask=CONF-RESET-MASK_

    // If reset is ever called, these are required before registers populate.
    // If resetting for other reasons, resets to the last configured mode.
    last-measure-mode := get-measure-mode
    set-shunt-resistor_ shunt-resistor_
    set-measure-mode last-measure-mode

  /**
  Gets the current calibration value.

  The calibration value scales the raw sensor data so that it corresponds to
    real-world values, taking into account the shunt resistor value, the
    full-scale range, and other system-specific factors. This value is
    calculated automatically by the $set-shunt-resistor_ method - setting
    manually is not normally required, and is private.  See Datasheet pp.10.
  */
  get-calibration-value_ -> int:
    return read-register_ REGISTER-CALIBRATION_
    //return reg_.read-u16-be REGISTER-CALIBRATION_

  /**
  Sets calibration value.  See $get-calibration-value_.
  */
  set-calibration-value_ value/int -> none:
    write-register_ REGISTER-CALIBRATION_ value

  /**
  Adjust Sampling Rate for measurements.

  The sampling rate determines how often the device samples and averages the
  input signals (bus voltage and shunt voltage) before storing them in the
  result registers.  More samples lead to more stable values, but can lengthen
  the time required for a single measurement.  This is the register code/enum
  value, not actual rate. Can be converted back using  $get-sampling-rate
  --count={enum}
  */
  set-sampling-rate code/int -> none:
    write-register_ REGISTER-CONFIG_ code --mask=CONF-AVERAGE-MASK_

  /**
  Return current sampling rate configuration.  See $set-sampling-rate
  */
  get-sampling-rate -> int:
    return read-register_ REGISTER-CONFIG_ --mask=CONF-AVERAGE-MASK_

  /**
  The time spent by the ADC on a single measurement.

  Individual values are set for either the shunt or the bus voltage.
  - Longer time = more samples averaged inside = less noise, higher resolution.
  - Shorter time = fewer samples = faster updates, but noisier.
  Both Bus and Shunt have separate conversion times
  - Bus voltage = the "supply" or "load node" being monitored.
  - Shunt voltage = the tiny drop across the shunt resistor.
  - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt.

  Configure using statics 'TIMING-***-US'.
  */
  set-bus-conversion-time code/int -> none:
    write-register_ REGISTER-CONFIG_ code --mask=CONF-BUSVC-MASK_

  /**
  Gets conversion-time for bus only. See toitdoc for '$set-bus-conversion-time'.

  Returns one of the statics 'TIMING-***-US'.
  */
  get-bus-conversion-time -> int:
    return read-register_ REGISTER-CONFIG_ --mask=CONF-BUSVC-MASK_

  /**
  Sets conversion-time for shunt only. See toitdoc for '$set-bus-conversion-time'.

  Configure using statics 'TIMING-***-US'.
  */
  set-shunt-conversion-time code/int -> none:
    write-register_ REGISTER-CONFIG_ code --mask=CONF-SHUNTVC-MASK_

  /**
  Gets conversion-time for shunt only. See toitdoc for '$set-bus-conversion-time'.

  Returns one of the statics 'TIMING-***-US'.
  */
  get-shunt-conversion-time -> int:
    return read-register_ REGISTER-CONFIG_ --mask=CONF-SHUNTVC-MASK_

  /**
  Sets Measure Mode.

  One of $MODE-POWER-DOWN, $MODE-TRIGGERED or $MODE-CONTINUOUS.
  See section 6.6 of the Datasheet titled 'Electrical Characteristics'.
  */
  set-measure-mode mode/int -> none:
    write-register_ REGISTER-CONFIG_ mode --mask=CONF-MODE-MASK_

  /**
  Gets configured Measure Mode. See $set-measure-mode.
  */
  get-measure-mode -> int:
    return read-register_ REGISTER-CONFIG_ --mask=CONF-MODE-MASK_

  /**
  Sets the resistor and current range.  See README.md
  */
  set-shunt-resistor_ resistor/float --max-current/float=(SHUNT-FULL-SCALE-VOLTAGE-LIMIT_/resistor) -> none:
    // Cache to class-wide for later use.
    shunt-resistor_ = resistor
    // Cache to class-wide for later use.
    max-current_ = max-current
    // Cache LSB of max current selection (amps per bit).
    current-LSB_ = (max-current_ / 32768.0)
    // Calculate new calibration value.
    new-calibration-value  := INTERNAL_SCALING_VALUE_ / (current-LSB_ * resistor)
    // Set the new calibration value in the IC.
    set-calibration-value_  (new-calibration-value).round
    // Cache new current divider LSB
    current-divider-ma_    = 0.001 / current-LSB_
    // Cache new power multiplier/LSB
    power-multiplier-mw_   = 1000.0 * 25.0 * current-LSB_

  /**
  Returns shunt current in amps.

  The INA226 doesn't measure current directly—it measures the voltage drop
  across this shunt resistor and calculates current using Ohm’s Law.
  */
  read-shunt-current -> float:
    value   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    //logger_.debug "method1=$(%0.6f value * current-LSB_) method2=$(%0.6f value * SHUNT-VOLTAGE-LSB_ / shunt-resistor_)"
    return value * current-LSB_

  /**
  Returns shunt voltage in volts.

  The shunt voltage is the voltage drop across the shunt resistor, which allows
  the INA226 to calculate current. The INA226 measures this voltage to calculate
  the current flowing through the load.
  */
  read-shunt-voltage -> float:
    value := reg_.read-i16-be REGISTER-SHUNT-VOLTAGE_
    return value * SHUNT-VOLTAGE-LSB_

  /**
  Returns upstream voltage, before the shunt (IN+).

  This is the rail straight from the power source, minus any drop across the
  shunt. Since INA226 doesn’t have a dedicated pin for this, it can be
  reconstructed by: Vsupply = Vbus + Vshunt.  i.e. adding the measured bus
  voltage (load side) and the measured shunt voltage.
  */
  read-supply-voltage -> float:
    return read-bus-voltage + read-shunt-voltage

  /**
  Return voltage of whatever is wired to the VBUS pin.

  On most breakout boards, VBUS is tied internally to IN− (the low side of the shunt). So in
  practice, “bus voltage” usually means the voltage at the load side of the shunt.  This is
  what the load actually sees as its supply rail.
  */
  read-bus-voltage -> float:
    value := reg_.read-i16-be REGISTER-BUS-VOLTAGE_
    return value * BUS-VOLTAGE-LSB_

  /**
  Watts used by the load.

  Calculated using the cached multiplier: [power-multiplier-mw_ = 1000 * 25 * current-LSB_]
  */
  read-load-power -> float:
    value := reg_.read-u16-be REGISTER-LOAD-POWER_
    return (value * power-multiplier-mw_).to-float / 1000.0

  /**
  Waits for 'conversion-ready', with a maximum wait of $get-estimated-conversion-time-ms.
  */
  wait-until-conversion-completed --max-wait-time-ms/int=(get-estimated-conversion-time-ms) -> none:
    current-wait-time-ms/int   := 0
    sleep-interval-ms/int := 50
    while (not conversion-ready):                                                      // Checks if sampling is completed.
      sleep --ms=sleep-interval-ms
      current-wait-time-ms += sleep-interval-ms
      if current-wait-time-ms >= max-wait-time-ms:
        logger_.debug "wait-until-conversion-completed: max-wait-time exceeded - continuing" --tags={ "max-wait-time-ms" : max-wait-time-ms }
        break

  /**
  Perform a single conversion/measurement - without waiting.

  If in TRIGGERED MODE:  Executes one measurement.
  If in CONTINUOUS MODE: Immediately refreshes data.
  */
  trigger-measurement --wait/bool=false -> none:
    // If in triggered mode, wait by default.
    should-wait/bool := get-measure-mode == MODE-TRIGGERED

    // Reading this mask clears the CNVR (Conversion Ready) Flag.
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_

    // Rewriting the mode bits starts a conversion.
    raw := read-register_ REGISTER-CONFIG_ --mask=CONF-MODE-MASK_
    write-register_ REGISTER-MASK-ENABLE_ raw --mask=CONF-MODE-MASK_

    // Wait if required. If in triggered mode, wait by default, respect switch.
    if should-wait or wait: wait-until-conversion-completed

  /**
  Sets shunt 'is over voltage' alert.  See README.md.
  */
  set-shunt-over-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / SHUNT-VOLTAGE-LSB_).round
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-SHUNT-OVER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets shunt 'is under voltage' alert.  See README.md.
  */
  set-shunt-under-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / SHUNT-VOLTAGE-LSB_).round
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-SHUNT-UNDER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets shunt 'is over current' alert by mathing to voltage.  See README.md.
  */
  set-shunt-over-current-alert amps/float -> none:
    disable-all-alerts
    full-scale-current := (SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / shunt-resistor_)
    if amps > full-scale-current:
      logger_.warn "set-shunt-over-current-alert: limit $(%0.6f amps) A exceeds full-scale $(%0.6f full-scale-current) A; clamping."
      amps = full-scale-current
    raw-limit/int := (amps * shunt-resistor_ / SHUNT-VOLTAGE-LSB_).round
    raw-limit = clamp-value raw-limit --upper=32767 --lower=-32768
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-SHUNT-OVER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets shunt 'is under current' alert by mathing to voltage.  See README.md.
  */
  set-shunt-under-current-alert amps/float -> none:
    disable-all-alerts
    full-scale-current := (SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / shunt-resistor_)
    if amps > full-scale-current:
      logger_.warn "set-shunt-over-current-alert: limit $(%0.6f amps) A exceeds full-scale $(%0.6f full-scale-current) A; clamping."
      amps = full-scale-current
    raw-limit/int := (amps * shunt-resistor_ / SHUNT-VOLTAGE-LSB_).round
    raw-limit = clamp-value raw-limit --upper=32767 --lower=-32768
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-SHUNT-UNDER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets bus 'is over voltage' alert.  See README.md.
  */
  set-bus-over-voltage-alert volts/float -> none:
    disable-all-alerts
    raw-limit/int := (volts / BUS-VOLTAGE-LSB_).round
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-BUS-OVER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets bus 'is under voltage' alert.  See README.md.
  */
  set-bus-under-voltage-alert volts/float -> none:
    disable-all-alerts
    raw-limit/int := (volts / BUS-VOLTAGE-LSB_ ).round
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-BUS-UNDER-VOLTAGE_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets power 'is over wattage' alert.  See README.md.
  */
  set-power-over-alert watts/float -> none:
    disable-all-alerts
    //raw-limit/int := (limit / power-multiplier-mw_).round
    raw-limit/int := (watts / (25 * current_LSB_)).round
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-POWER-OVER_
    write-register_ REGISTER-ALERT-LIMIT_ raw-limit

  /**
  Sets 'conversion-ready' alert to use the pin.
  */
  set-conversion-ready-alert -> none:
    disable-all-alerts
    write-register_ REGISTER-MASK-ENABLE_ 1 --mask=ALERT-ENABLE-CONVERSION-READY_

  /**
  Disables all alerts.  Useful when setting a new alert type.
  */
  disable-all-alerts -> none:
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-SHUNT-OVER-VOLTAGE_
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-SHUNT-UNDER-VOLTAGE_
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-BUS-OVER-VOLTAGE_
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-BUS-UNDER-VOLTAGE_
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-POWER-OVER_
    write-register_ REGISTER-MASK-ENABLE_ 0 --mask=ALERT-ENABLE-CONVERSION-READY_

  /**
  Sets Alert "Latching".

  When the Alert Latch Enable bit is set to Transparent mode, the Alert pin and Flag bit
  resets to the idle states when the fault has been cleared.  When the Alert Latch Enable bit
  is set to Latch mode, the Alert pin and Alert Flag bit remains active following a fault
  until the Mask/Enable Register has been read.
  - 1 = Latch enabled
  - 0 = Transparent (default)
  */
  set-alert-latching set/int -> none:
    assert: 0 <= set <= 1
    write-register_ REGISTER-MASK-ENABLE_ set --mask=ALERT-LATCH-ENABLE_

  /**
  Sets alert pin polarity function.

  Settings:
  - 1 = Inverted (active-high open collector).
  - 0 = Normal (active-low open collector) (default).
  */
  set-alert-pin-polarity set/int -> none:
    assert: 0 <= set <= 1
    write-register_ REGISTER-MASK-ENABLE_ set --mask=ALERT-PIN-POLARITY_

  /**
  Get configured alert pin polarity setting. See '$set-alert-pin-polarity'.
  */
  get-alert-pin-polarity -> int:
    return read-register_ REGISTER-MASK-ENABLE_ --mask=ALERT-PIN-POLARITY_

  /**
  Clears alerts.

  Test well when used: datasheet suggests simply reading the MASK-ENABLE is enough to clear any alerts.
  */
  clear-alert -> none:
    register/int := read-register_ REGISTER-MASK-ENABLE_

  /**
  Returns True if a conversion is complete.

  Although the device can be read at any time, and the data from the last
  conversion is available, the Conversion Ready Flag bit is provided to help
  coordinate one-shot or triggered conversions. The Conversion Ready Flag bit is
  set after all conversions, averaging, and multiplications are complete.
  Conversion Ready Flag bit clears under the following conditions:
    1. Writing to the Configuration Register (except when Power-Down).
    2. Reading the Mask/Enable Register (Implemented in $clear-alert).
  */
  conversion-ready -> bool:
    raw/int := read-register_ REGISTER-MASK-ENABLE_ --mask=CONVERSION-READY-ALERT-FLAG_
    return raw == 1

  /**
  Returns true if an overflow alert exists.

  This bit is set to '1' if an arithmetic operation resulted in an overflow error. The
  bit indicates that current and power data can be invalid.
  */
  alert-overflow  -> bool:
    raw/int := read-register_ REGISTER-MASK-ENABLE_ --mask=MATH-OVERFLOW-ALERT-FLAG_
    return raw == 1

  /**
  Returns true if any of the set alert limits are exceeded.

  While only one Alert Function can be monitored at the Alert pin at a
  time, the Conversion Ready can also be enabled to assert the Alert pin. Reading
  the Alert Function Flag following an alert allows the user to determine if the
  Alert Function is the source of the Alert.

  When the Alert Latch Enable bit is set to Latch mode, the Alert Function Flag
  bit clears only when the Mask/Enable Register is read. When the Alert Latch
  Enable bit is set to Transparent mode, the Alert Function Flag bit is cleared
  following the next conversion that does not result in an Alert condition.
  */
  alert-limit -> bool:
    raw/bool := read-register_ REGISTER-MASK-ENABLE_ --mask=FUNCTION-ALERT-FLAG_
    return raw == 1

  /**
  Returns us for supplied TIMING-x-US register values 0..7.
  */
  get-conversion-time-us-from-enum code/int -> int:
    assert: 0 <= code <= 7
    if code == TIMING-140-US:  return 140
    if code == TIMING-204-US:  return 204
    if code == TIMING-332-US:  return 332
    if code == TIMING-588-US:  return 588
    if code == TIMING-1100-US: return 1100
    if code == TIMING-2100-US: return 2100
    if code == TIMING-4200-US: return 4200
    if code == TIMING-8300-US: return 8300
    return 1100  // default/defensive - should never happen

  /**
  Returns sampling count for AVERAGE-x-SAMPLE register values.
  */
  get-sampling-rate-from-enum code/int -> int:
    assert: 0 <= code <= 7
    if code == AVERAGE-1-SAMPLE:     return 1
    if code == AVERAGE-4-SAMPLES:    return 4
    if code == AVERAGE-16-SAMPLES:   return 16
    if code == AVERAGE-64-SAMPLES:   return 64
    if code == AVERAGE-128-SAMPLES:  return 128
    if code == AVERAGE-256-SAMPLES:  return 256
    if code == AVERAGE-512-SAMPLES:  return 512
    if code == AVERAGE-1024-SAMPLES: return 1024
    return 1  // default/defensive - should never happen

  /**
  Estimate a worst-case maximum waiting time (+10%) based on the configuration.

  Done this way to prevent setting a max-wait type value of the worst case
  situation for all situations.
  */
  get-estimated-conversion-time-ms -> int:
    // Read config and decode fields using masks/offsets
    sampling-rate/int         := get-sampling-rate-from-enum get-sampling-rate
    bus-conversion-time/int   := get-conversion-time-us-from-enum get-bus-conversion-time
    shunt-conversion-time/int := get-conversion-time-us-from-enum get-shunt-conversion-time
    total-us/int              := (bus-conversion-time + shunt-conversion-time) * sampling-rate

    // Add a small guard factor (~10%) to be conservative.
    total-us = ((total-us * 11.0) / 10.0).round

    // Return milliseconds, minimum 1 ms
    total-ms := ((total-us + 999) / 1000)  // Ceiling.
    if total-ms < 1: total-ms = 1

    //logger_.debug "get-estimated-conversion-time-ms:"  --tags={ "get-estimated-conversion-time-ms" : total-ms }
    return total-ms

  /**
  Get Manufacturer identifier.  Useful for identifying INA family devices.
  */
  read-manufacturer-id -> int:
    return reg_.read-u16-be REGISTER-MANUF-ID_

  /**
  Returns device ID part of the DIE-ID register. (Bits 4-15)
  */
  read-device-identification -> int:
    return read-register_ REGISTER-DIE-ID_ --mask=DIE-ID-DID-MASK_

  /**
  Returns Die Revision Bits from the register. (Bits 0-3)
  */
  read-device-revision -> int:
    return read-register_ REGISTER-DIE-ID_ --mask=DIE-ID-RID-MASK_

  /**
  Reads the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF and offset at 0x0, it is treated as a read from the whole
  register.
  */
  read-register_ register/int --mask/int=0xFFFF --offset/int=(mask.count-trailing-zeros) -> any:
    register-value := reg_.read-u16-be register
    if mask == 0xFFFF and offset == 0:
      //logger_.debug "read-register_:" --tags={ "register" : register , "register-value" : register-value }
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      //logger_.debug "read-register_:"  --tags={ "register" : register , "register-value" : register-value, "mask" : mask , "offset" : offset}
      return masked-value

  /**
  Writes the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF and offset at 0x0, it is treated as a write to the whole
  register.
  */
  write-register_ register/int value/any --mask/int=0xFFFF --offset/int=(mask.count-trailing-zeros) -> none:
    // find allowed value range within field
    max/int := mask >> offset
    // check the value fits the field
    assert: ((value & ~max) == 0)

    if (mask == 0xFFFF) and (offset == 0):
      reg_.write-u16-be register (value & 0xFFFF)
    else:
      new-value/int := reg_.read-u16-be register
      new-value     &= ~mask
      new-value     |= (value << offset)
      reg_.write-u16-be register new-value

  /**
  Clamps the supplied value to specified limit.
  */
  clamp-value value/any --upper/any?=null --lower/any?=null -> any:
    if upper != null: if value > upper:  return upper
    if lower != null: if value < lower:  return lower
    return value

  /**
  Print Diagnostic Information.

  Prints relevant measurement information allowing someone with a Voltmeter to
  double check what is measured and compare it.  Also tries to self-check a
  little by calculating/comparing using Ohms Law (V=I*R).
  */
  print-diagnostics -> none:
    // Optional: ensure fresh data.
    trigger-measurement --wait
    wait-until-conversion-completed

    shunt-voltage/float                := read-shunt-voltage
    load-voltage/float                 := read-bus-voltage                   // what the load actually sees (Vbus, eg IN−).
    supply-voltage/float               := load-voltage + shunt-voltage       // upstream rail (IN+ = IN− + Vshunt).
    shunt-voltage-delta/float          := supply-voltage - load-voltage      // same as Vshunt.
    shunt-voltage-delta-percent/float  := 0.0
    if supply-voltage > 0.0: shunt-voltage-delta-percent = (shunt-voltage-delta / supply-voltage) * 100.0

    calibration-value/int              := get-calibration-value_
    current-raw/int                    := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    least-significant-bit/float        := 0.00512 / (calibration-value.to-float * shunt-resistor_)
    current-chip/float                 := current-raw * least-significant-bit
    current-v-r/float                  := shunt-voltage / shunt-resistor_

    // CROSSCHECK: between chip/measured current and V/R reconstructed current.
    current-difference/float           := (current-chip - current-v-r).abs
    current-difference-percent/float   := 0.0
    if (current-v-r != 0.0):
      current-difference-percent       = (current-difference / current-v-r) * 100.0

    // CROSSCHECK: shunt voltage (measured vs reconstructed).
    shunt-voltage-calculated/float          := current-chip * shunt-resistor_
    shunt-voltage-difference/float          := (shunt-voltage - shunt-voltage-calculated).abs
    shunt-voltage-difference-percent/float  := 0.0
    if (shunt-voltage != 0.0):
      shunt-voltage-difference-percent      = (shunt-voltage-difference / shunt-voltage).abs * 100.0

    print "DIAG :"
    print "    ----------------------------------------------------------"
    print "    Shunt Resistor      =  $(%0.8f shunt-resistor_) Ohm (Configured in code)"
    print "    Vload    (IN-)      =  $(%0.8f load-voltage)  V"
    print "    Vsupply  (IN+)      =  $(%0.8f supply-voltage)  V"
    print "    Shunt Voltage delta =  $(%0.8f shunt-voltage-delta)  V"
    print "                        = ($(%0.8f shunt-voltage-delta*1000.0)  mV)"
    print "                        = ($(%0.3f shunt-voltage-delta-percent)% of supply)"
    print "    Vshunt (direct)     =  $(%0.8f shunt-voltage)  V"
    print "    ----------------------------------------------------------"
    print "    Calibration Value   =  $(calibration-value)"
    print "    I (raw register)    = ($(current-raw))"
    print "                 LSB    = ($(%0.8f least-significant-bit)  A/LSB)"
    print "    I (from module)     =  $(%0.8f current-chip)  A"
    print "    I (from V/R)        =  $(%0.8f current-v-r)  A"
    print "    ----------------------------------------------------------"
    if current-difference-percent < 5.0:
      print "    Check Current       : OK - Currents agree ($(%0.3f current-difference-percent)% under/within 5%)"
    else if current-difference-percent < 20.0:
      print "    Check Current       : WARNING (5% < $(%0.3f current-difference-percent)% < 20%) - differ noticeably"
    else:
      print "    Check Current       : BAD!! ($(%0.3f current-difference-percent)% > 20%): check calibration or shunt value"
    if shunt-voltage-difference-percent < 5.0:
      print "    Check Shunt Voltage : OK - Shunt voltages agree ($(%0.3f shunt-voltage-difference-percent)% under/within 5%)"
    else if shunt-voltage-difference-percent < 20.0:
      print "    Check Shunt Voltage : WARNING (5% < $(%0.3f shunt-voltage-difference-percent)% < 20%) - differ noticeably"
    else:
      print "    Check Shunt Voltage : BAD!! ($(%0.3f shunt-voltage-difference-percent)% > 20%): shunt voltage mismatch"

  /**
  Provides strings to display bitmasks nicely when testing.
  */
  bits-16_ x/int --min-display-bits/int=0 -> string:
    if (x > 255) or (min-display-bits > 8):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 16 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16])"
      return out-string
    else if (x > 15) or (min-display-bits > 4):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 8 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8])"
      return out-string
    else:
      out-string := "$(%b x)"
      out-string = out-string.pad --left 4 '0'
      out-string = "$(out-string[0..4])"
      return out-string
