
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

To use this library, first consult the examples.  Several values must be set
before data will be available.  These are set using the class to default values
to allow for immediate use.  - Most variants I have personally seen have an R100
  shunt resistor.  If the shunt resistor is not R100 (0.100 Ohm) ensure to set
this in the class after intantiation.  (See the examples!) - Ensure sample size
  is set appropriately - a higher sample size will ensure more stable
  measurements, although changes will be slower to be visible.

*/


class Ina226:
  /**
  Default $I2C-ADDRESS is 64 (0x40).  Valid addresses: 64 to 79.
  */
  static I2C-ADDRESS                            ::= 0x40

  /**
  MODE constants to be used by users during configuration with $set-measure-mode
  */
  static MODE-POWER-DOWN                       ::= 0b000
  static MODE-TRIGGERED                        ::= 0b011
  static MODE-CONTINUOUS                       ::= 0b111 // Class Default.

  /**
  Alert Types for alert functions.
  */
  static ALERT-SHUNT-OVER-VOLTAGE_             ::= 0b10000000_00000000
  static ALERT-SHUNT-OVER-VOLTAGE-OFFSET_      ::= 15
  static ALERT-SHUNT-UNDER-VOLTAGE_            ::= 0b01000000_00000000
  static ALERT-SHUNT-UNDER-VOLTAGE-OFFSET_     ::= 14
  static ALERT-BUS-OVER-VOLTAGE_               ::= 0b00100000_00000000
  static ALERT-BUS-OVER-VOLTAGE-OFFSET_        ::= 13
  static ALERT-BUS-UNDER-VOLTAGE_              ::= 0b00010000_00000000
  static ALERT-BUS-UNDER-VOLTAGE-OFFSET_       ::= 12
  static ALERT-POWER-OVER_                     ::= 0b00001000_00000000
  static ALERT-POWER-OVER-OFFSET_              ::= 11
  static ALERT-CONVERSION-READY_               ::= 0b00000100_00000000
  static ALERT-CONVERSION-READY-OFFSET_        ::= 10
  static ALERT-PIN-POLARITY_                   ::= 0b00000000_00000010
  static ALERT-PIN-POLARITY-OFFSET_            ::= 1
  static ALERT-LATCH-ENABLE_                   ::= 0b00000000_00000001
  static ALERT-LATCH-ENABLE-OFFSET_            ::= 0

  /**
  Actual Alert Flags
  */
  static FUNCTION-ALERT-FLAG_                  ::= 0b00000000_00010000
  static FUNCTION-ALERT-OFFSET_                ::= 4
  static MATH-OVERFLOW-ALERT-FLAG_             ::= 0b00000000_00000100
  static MATH-OVERFLOW-ALERT-OFFSET_           ::= 2
  static CONVERSION-READY-ALERT-FLAG_          ::= 0b00000100_00001000
  static CONVERSION-READY-ALERT-OFFSET_        ::= 3


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

  /**
  Bus and Shunt conversion timing options.

  To be used with $set-bus-conversion-time and $set-shunt-conversion-time.
  */
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

  // Die & Manufacturer Info Masks.
  static DIE-ID-RID-MASK_                      ::= 0x000F //R  // Masks its part of the REGISTER-DIE-ID Register
  static DIE-ID-DID-MASK_                      ::= 0xFFF0 //R  // Masks its part of the REGISTER-DIE-ID Register

  // Actual INA226 device ID - to identify this chip over INA3221 etc.
  static INA226-DEVICE-ID_                     ::= 0x0226

  // Configuration Register bitmasks.
  static CONF-RESET-MASK_                      ::= 0x8000
  static CONF-RESET-OFFSET_                    ::= 15
  static CONF-AVERAGE-MASK_                    ::= 0x0E00
  static CONF-AVERAGE-OFFSET_                  ::= 9
  static CONF-SHUNTVC-MASK_                    ::= 0x0038
  static CONF-SHUNTVC-OFFSET_                  ::= 3
  static CONF-BUSVC-MASK_                      ::= 0x01C0
  static CONF-BUSVC-OFFSET_                    ::= 6
  static CONF-MODE-MASK_                       ::= 0x0007
  static CONF-MODE-OFFSET_                     ::= 0

  static INTERNAL_SCALING_VALUE_/float         ::= 0.00512
  static SHUNT-FULL-SCALE-VOLTAGE-LIMIT_/float ::= 0.08192    // volts.
  static SHUNT-VOLTAGE-LSB_                    ::= 0.0000025  // volts. 2.5 µV/bit.
  static BUS-VOLTAGE-LSB_                      ::= 0.00125    // volts, 1.25 mV/bit

  // Private variables.
  reg_/registers.Registers := ?
  logger_/log.Logger := ?
  current-divider-ma_/float := 0.0
  power-multiplier-mw_/float := 0.0
  last-measure-mode_/int := MODE-CONTINUOUS
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
    set-shunt-resistor_ shunt-resistor
    set-measure-mode measure-mode

    if (read-device-identification != INA226-DEVICE-ID_):
      logger_.error "Device is NOT an INA226 (0x$(%04x INA226-DEVICE-ID_) [Device ID:0x$(%04x read-device-identification)]) "
      logger_.error "Device is man-id=0x$(%04x read-manufacturer-id) dev-id=0x$(%04x read-device-identification) rev=0x$(%04x read-device-revision)"
      throw "Device is not an INA226."

    initialize_

  /**
  Initial Device Configuration
  */
  initialize_ -> none:
    // Maybe not required but the manual suggests you should do it.
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
    write-register_ --register=REGISTER-CONFIG_ --mask=CONF-RESET-MASK_ --offset=CONF-RESET-OFFSET_ --value=0b1

  /**
  Gets the current calibration value.

  The calibration value scales the raw sensor data so that it corresponds to
    real-world values, taking into account the shunt resistor value, the
    full-scale range, and other system-specific factors. This value is
    calculated automatically by the $set-shunt-resistor_ method - setting
    manually is not normally required.  See Datasheet pp.10.
  */
  get-calibration-value -> int:
    return read-register_ --register=REGISTER-CALIBRATION_
    //return reg_.read-u16-be REGISTER-CALIBRATION_

  /**
  Sets calibration value.  See $get-calibration-value.
  */
  set-calibration-value value/int -> none:
    write-register_ --register=REGISTER-CALIBRATION_ --value=value

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
    write-register_ --register=REGISTER-CONFIG_ --mask=CONF-AVERAGE-MASK_ --offset=CONF-AVERAGE-OFFSET_ --value=code

  /**
  Return current sampling rate configuration.  See $set-sampling-rate
  */
  get-sampling-rate -> int:
    return read-register_ --register=REGISTER-CONFIG_ --mask=CONF-AVERAGE-MASK_ --offset=CONF-AVERAGE-OFFSET_

  /**
  Return sampling count number in us.  See $set-sampling-rate
  */
  get-sampling-rate-us -> int:
    return get-sampling-rate-from-enum get-sampling-rate

  /**
  The time spent by the ADC on a single measurement.

  Individual values are set for either the shunt or the bus voltage.
  - Longer time = more samples averaged inside = less noise, higher resolution.
  - Shorter time = fewer samples = faster updates, but noisier.
  Both Bus and Shunt have separate conversion times
  - Bus voltage = the “supply” or “load node” you’re monitoring.
  - Shunt voltage = the tiny drop across your shunt resistor.
  - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt.
  */
  set-bus-conversion-time code/int -> none:
    write-register_ --register=REGISTER-CONFIG_ --mask=CONF-BUSVC-MASK_ --offset=CONF-BUSVC-OFFSET_ --value=code

  /**
  Gets conversion-time for bus only. See 'Conversion Time'.
  */
  get-bus-conversion-time -> int:
    return read-register_ --register=REGISTER-CONFIG_ --mask=CONF-BUSVC-MASK_ --offset=CONF-BUSVC-OFFSET_

  /**
  Sets conversion-time for shunt only. See 'Conversion Time'.
  */
  set-shunt-conversion-time code/int -> none:
    write-register_ --register=REGISTER-CONFIG_ --mask=CONF-SHUNTVC-MASK_ --offset=CONF-SHUNTVC-OFFSET_ --value=code

  /**
  Gets conversion-time for shunt only. See 'Conversion Time'.
  */
  get-shunt-conversion-time -> int:
    return read-register_ --register=REGISTER-CONFIG_ --mask=CONF-SHUNTVC-MASK_ --offset=CONF-SHUNTVC-OFFSET_


  /**
  Sets Measure Mode.

  One of INA226-MODE-POWER-DOWN, INA226-MODE-TRIGGERED or
  INA226-MODE-CONTINUOUS.  Keeps track of last measure mode set, in a local
  variable, to ensures device comes back on into the same previous mode when
  using 'power-on' and power-off functions.  See section 6.6 of the Datasheet
  'Electrical Characteristics'.
  */
  set-measure-mode mode/int -> none:
    write-register_ --register=REGISTER-CONFIG_ --mask=CONF-MODE-MASK_ --offset=CONF-MODE-OFFSET_ --value=mode
    if (mode != MODE-POWER-DOWN): last-measure-mode_ = mode

  /**
  Gets configured Measure Mode. See $set-measure-mode.
  */
  get-measure-mode -> int:
    return read-register_ --register=REGISTER-CONFIG_ --mask=CONF-MODE-MASK_ --offset=CONF-MODE-OFFSET_

  /**
  Powers off the device. See $set-measure-mode.
  */
  set-power-off -> none:
    set-measure-mode MODE-POWER-DOWN

  /**
  Powers on the device. See $set-measure-mode. Resets to the last mode set.
  */
  set-power-on -> none:
    set-measure-mode last-measure-mode_
    sleep --ms=(get-estimated-conversion-time-ms)

  /**
  Sets the resistor and current range.  See README.md
  */
  set-shunt-resistor_ resistor/float --max-current/float=(SHUNT-FULL-SCALE-VOLTAGE-LIMIT_/resistor) -> none:
    shunt-resistor_        = resistor                                              // Cache to class-wide for later use.
    max-current_           = max-current                                           // Cache to class-wide for later use.
    current-LSB_           = (max-current_ / 32768.0)                              // Amps per bit (eg. LSB).
    //logger_.debug "shunt-resistor: current per bit = $(current-LSB_)A"
    new-calibration-value  := INTERNAL_SCALING_VALUE_ / (current-LSB_ * resistor)
    //logger_.debug "shunt-resistor: calibration value becomes = $(new-calibration-value) $((new-calibration-value).round)[rounded]"
    set-calibration-value  (new-calibration-value).round
    current-divider-ma_    = 0.001 / current-LSB_
    power-multiplier-mw_   = 1000.0 * 25.0 * current-LSB_
    //logger_.debug "shunt-resistor: (32767 * current-LSB_)=$(32767 * current-LSB_) compared to $(max-current_)"

  /**
  Returns shunt current in amps.

  The INA226 doesn't measure current directly—it measures the voltage drop
  across this shunt resistor and calculates current using Ohm’s Law.
  */
  read-shunt-current -> float:
    value   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    //logger_.debug "method1=$(%0.6f value * current-LSB_) method2=$(%0.6f value * SHUNT-VOLTAGE-LSB_ / shunt-resistor_)"
    return (value * current-LSB_)

  /**
  Returns shunt voltage in volts.

  The shunt voltage is the voltage drop across the shunt resistor, which allows
  the INA226 to calculate current. The INA226 measures this voltage to calculate
  the current flowing through the load.
  */
  read-shunt-voltage -> float:
    value := reg_.read-i16-be REGISTER-SHUNT-VOLTAGE_
    return (value * SHUNT-VOLTAGE-LSB_)

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
    return ((value * power-multiplier-mw_).to-float / 1000.0)

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
        logger_.debug "wait-until-conversion-completed: maxWaitTime $(max-wait-time-ms)ms exceeded - continuing"
        break

  /**
  Perform a single conversion/measurement - without waiting.

  If in TRIGGERED MODE:  Executes one measurement.
  If in CONTINUOUS MODE: Immediately refreshes data.
  */
  trigger-measurement --wait/bool=false -> none:
    should-wait/bool := last-measure-mode_ == MODE-TRIGGERED
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_        // Reading clears CNVR (Conversion Ready) Flag.
    config-register-value/int   := reg_.read-u16-be REGISTER-CONFIG_
    reg_.write-u16-be REGISTER-CONFIG_ config-register-value                   // Starts conversion.
    if should-wait or wait: wait-until-conversion-completed

  /**
  Sets shunt 'is over voltage' alert.  See README.md.
  */
  set-shunt-over-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / SHUNT-VOLTAGE-LSB_).round
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-OVER-VOLTAGE_ --offset=ALERT-SHUNT-OVER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit

  /**
  Sets shunt 'is under voltage' alert.  See README.md.
  */
  set-shunt-under-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / SHUNT-VOLTAGE-LSB_).round
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-UNDER-VOLTAGE_ --offset=ALERT-SHUNT-UNDER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit

  /**
  Sets shunt 'is over current' alert by mathing to voltage.  See README.md.
  */
  set-shunt-over-current-alert limit/float -> none:
    disable-all-alerts
    full-scale-current := (SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / shunt-resistor_)
    if limit > full-scale-current:
      logger_.warn "set-shunt-over-current-alert: limit $(%0.6f limit) A exceeds full-scale $(%0.6f full-scale-current) A; clamping."
      limit = full-scale-current
    raw-limit/int := (limit * shunt-resistor_ / SHUNT-VOLTAGE-LSB_).round
    raw-limit = clamp-value raw-limit --upper=32767 --lower=-32768
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-OVER-VOLTAGE_ --offset=ALERT-SHUNT-OVER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit

  /**
  Sets shunt 'is under current' alert by mathing to voltage.  See README.md.
  */
  set-shunt-under-current-alert limit/float -> none:
    disable-all-alerts
    full-scale-current := (SHUNT-FULL-SCALE-VOLTAGE-LIMIT_ / shunt-resistor_)
    if limit > full-scale-current:
      logger_.warn "set-shunt-over-current-alert: limit $(%0.6f limit) A exceeds full-scale $(%0.6f full-scale-current) A; clamping."
      limit = full-scale-current
    raw-limit/int := (limit * shunt-resistor_ / SHUNT-VOLTAGE-LSB_).round
    raw-limit = clamp-value raw-limit --upper=32767 --lower=-32768
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-UNDER-VOLTAGE_ --offset=ALERT-SHUNT-UNDER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit

  /**
  Sets bus 'is over voltage' alert.  See README.md.
  */
  set-bus-over-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / BUS-VOLTAGE-LSB_).round
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-BUS-OVER-VOLTAGE_ --offset=ALERT-BUS-OVER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit
    //raw-check-value := reg_.read-i16-be REGISTER-ALERT-LIMIT_
    //register-value  := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-BUS-OVER-VOLTAGE --offset=ALERT-BUS-OVER-VOLTAGE-MASK_
    //logger_.debug "set-power-over-alert ($(register-value)): raw=$(raw-check-value) mathed=$(raw-check-value * BUS-VOLTAGE-LSB_)"

  /**
  Sets bus 'is under voltage' alert.  See README.md.
  */
  set-bus-under-voltage-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / BUS-VOLTAGE-LSB_ ).round
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-BUS-UNDER-VOLTAGE_ --offset=ALERT-BUS-UNDER-VOLTAGE-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit
    //raw-check-value := reg_.read-i16-be REGISTER-ALERT-LIMIT_
    //logger_.debug "set-power-over-alert: raw=$(raw-check-value) mathed=$(raw-check-value * BUS-VOLTAGE-LSB_)"

  /**
  Sets power 'is over wattage' alert.  See README.md.
  */
  set-power-over-alert limit/float -> none:
    disable-all-alerts
    raw-limit/int := (limit / power-multiplier-mw_).round
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-POWER-OVER_ --offset=ALERT-POWER-OVER-OFFSET_ --value=1
    write-register_ --register=REGISTER-ALERT-LIMIT_ --value=raw-limit

  /**
  Sets 'conversion-ready' alert to use the pin.
  */
  set-conversion-ready-alert -> none:
    disable-all-alerts
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CONVERSION-READY_ --offset=ALERT-CONVERSION-READY-OFFSET_ --value=1

  /**
  Disables all alerts.  Useful when setting a new alert type.
  */
  disable-all-alerts -> none:
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-OVER-VOLTAGE_ --offset=ALERT-SHUNT-OVER-VOLTAGE-OFFSET_ --value=0
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-SHUNT-UNDER-VOLTAGE_ --offset=ALERT-SHUNT-UNDER-VOLTAGE-OFFSET_ --value=0
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-BUS-OVER-VOLTAGE_ --offset=ALERT-BUS-OVER-VOLTAGE-OFFSET_ --value=0
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-BUS-UNDER-VOLTAGE_ --offset=ALERT-BUS-UNDER-VOLTAGE-OFFSET_ --value=0
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-POWER-OVER_ --offset=ALERT-POWER-OVER-OFFSET_ --value=0
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-CONVERSION-READY_ --offset=ALERT-CONVERSION-READY-OFFSET_ --value=0

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
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-LATCH-ENABLE_ --offset=ALERT-LATCH-ENABLE-OFFSET_ --value=set

  /**
  Sets alert pin polarity function.

  Settings:
  - 1 = Inverted (active-high open collector).
  - 0 = Normal (active-low open collector) (default).
  */
  set-alert-pin-polarity set/int -> none:
    assert: 0 <= set <= 1
    write-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-PIN-POLARITY_ --offset=ALERT-PIN-POLARITY-OFFSET_ --value=set

  /**
  Get configured alert pin polarity setting. See '$set-alert-pin-polarity'.
  */
  get-alert-pin-polarity -> int:
    return read-register_ --register=REGISTER-MASK-ENABLE_ --mask=ALERT-PIN-POLARITY_ --offset=ALERT-PIN-POLARITY-OFFSET_

  /**
  Clears alerts.

  Test well when used: datasheet suggests simply reading the MASK-ENABLE is enough to clear any alerts.
  */
  clear-alert -> none:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_

  /**
  Returns True if a conversion is complete.

  Although the device can be read at any time, and the data from the last
  conversion is available, the Conversion Ready Flag bit is provided to help
  coordinate one-shot or triggered conversions. The Conversion Ready Flag bit is
  set after all conversions, averaging, and multiplications are complete.
  Conversion Ready Flag bit clears under the following conditions: 1. Writing to
      the Configuration Register (except for Power-Down selection).  2. Reading
      the Mask/Enable Register (Implemented in $clear-alert).
  */
  conversion-ready -> bool:
    raw/int := read-register_ --register=REGISTER-MASK-ENABLE_ --mask=CONVERSION-READY-ALERT-FLAG_ --offset=CONVERSION-READY-ALERT-OFFSET_
    return (raw == 1)

  /**
  Returns true if an overflow alert exists.

  This bit is set to '1' if an arithmetic operation resulted in an overflow error. The
  bit indicates that current and power data can be invalid.
  */
  alert-overflow  -> bool:
    over/bool := false
    if (read-register_ --register=REGISTER-MASK-ENABLE_ --mask=MATH-OVERFLOW-ALERT-FLAG_ --offset=MATH-OVERFLOW-ALERT-OFFSET_) == 1:
      over = true
    return over

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
    limit/bool := false
    if (read-register_ --register=REGISTER-MASK-ENABLE_ --mask=FUNCTION-ALERT-FLAG_ --offset=FUNCTION-ALERT-OFFSET_) == 1:
      limit = true
    return limit

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

  Done this way to prevent setting a maxWait type value for the worst case
  situation.
  */
  get-estimated-conversion-time-ms -> int:
    // Read config and decode fields using masks/offsets
    sampling-rate/int         := get-sampling-rate-from-enum get-sampling-rate
    bus-conversion-time/int   := get-conversion-time-us-from-enum get-bus-conversion-time
    shunt-conversion-time/int := get-conversion-time-us-from-enum get-shunt-conversion-time
    total-us/int               := (bus-conversion-time + shunt-conversion-time) * sampling-rate

    // Add a small guard factor (~10%) to be conservative.
    total-us = ((total-us * 11.0) / 10.0).round

    // Return milliseconds, minimum 1 ms
    total-ms := ((total-us + 999) / 1000)  // Ceiling.
    if total-ms < 1: total-ms = 1

    //logger_.debug "get-estimated-conversion-time-ms is: $(totalms)ms"
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
    return read-register_ --register=REGISTER-DIE-ID_ --mask=DIE-ID-DID-MASK_

  /**
  Returns Die Revision Bits from the register. (Bits 0-3)
  */
  read-device-revision -> int:
    return read-register_ --register=REGISTER-DIE-ID_ --mask=DIE-ID-RID-MASK_

  /**
  Reads the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF and offset at 0x0, it is treated as a read from the whole
  register.
  */
  read-register_ --register/int --mask/int=0xFFFF --offset/int=0 -> any:
    register-value := reg_.read-u16-be register
    if mask == 0xFFFF and offset == 0:
      //logger_.debug "read-register_: reg-0x$(%02x register) is $(%04x register-value)"
      return register-value
    else:
      masked-value := (register-value & mask) >> offset
      //logger_.debug "read-register_: reg-0x$(%02x register) is $(bits-16_ register-value) mask=[$(bits-16_ mask) + offset=$(offset)] [$(bits-16_ masked-value)]"
      return masked-value

  /**
  Writes the given register with the supplied mask.

  Given that register reads are largely similar, implemented here.  If the mask
  is left at 0xFFFF and offset at 0x0, it is treated as a write to the whole
  register.
  */
  write-register_ --register/int --mask/int=0xFFFF --offset/int=(mask.count-trailing-zeros) --value/any --note/string="" -> none:
    max/int := mask >> offset                // allowed value range within field
    assert: ((value & ~max) == 0)            // value fits the field
    old-value/int := reg_.read-u16-be register

    // Split out the simple case
    if (mask == 0xFFFF) and (offset == 0):
      reg_.write-u16-be register (value & 0xFFFF)
      //logger_.debug "write-register_: Register 0x$(%02x register) set from $(%04x old-value) to $(%04x value) $(note)"
    else:
      new-value/int := old-value
      new-value     &= ~mask
      new-value     |= (value << offset)
      reg_.write-u16-be register new-value
      //logger_.debug "write-register_: Register 0x$(%02x register) set from $(bits-16_ old-value) to $(bits-16_ new-value) $(note)"

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
  double check what is measured and compare it.  Also calculates/compares using
  Ohms Law (V=I*R).
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

    calibration-value/int              := get-calibration-value
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
