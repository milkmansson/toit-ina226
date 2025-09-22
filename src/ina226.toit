
// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.   This file also includes derivative 
// work from other authors and sources.  See accompanying documentation.

import log
import binary
import serial.device as serial
import serial.registers as registers

/**
Toit Driver Library for an INA226 module, DC Shunt current and power sensor.

Several common modules exist based on the TI INA226 chip. 
Datasheet: https://www.ti.com/lit/ds/symlink/ina226.pdf 
One example: https://esphome.io/components/sensor/ina226/.  There are others with different
feature sets and may be partially code compatible.
- For all sensor reads, values are floats, and supplied in base SI units: volts, amps and watts.
- get-* and set-* methods/functions are used for setting properties about the class or the sensor itself.
- read-* methods/functions are used for getting reading actual sensor values 

To use this library, first consult the examples.  Several values must be set before data will
be available.  These are set using the class to default values to allow for immediate use.  
- Most variants I have personally seen have an R100 shunt resistor.  If the shunt resistor is
  not R100 (0.100 Ohm) ensure to set this in the class after intantiation.  (See the examples!)
- Ensure sample size is set appropriately - a higher sample size will ensure more stable 
  measurements, although changes will be slower to be visible.

Examples in the `examples` folder:
- Use Case 1: Simple Continuous Measurement.  The simplest use case.
- Use Case 2: Adjusting the Shunt Resistor to measure (for example, smaller) currents.
- Use Case 3: Triggered Updates - low power mode for infrequent/intermittent updates.
*/


class Ina226:
  /**
  Default $I2C-ADDRESS is 64 (0x40) with jumper defaults.
  
  Valid address values: 64 to 79 - See datasheet table 6-2
  */
  static I2C-ADDRESS                     ::= 0x40

  /** 
  MODE constants to be used by users during configuration with $set-measure-mode
  */
  static MODE-POWER-DOWN                 ::= 0x00
  static MODE-TRIGGERED                  ::= 0x03
  static MODE-CONTINUOUS                 ::= 0x07 // Class Default.

  /**
  Alert Types that can set off the alert register and/or alert pin. See $set-alert
  */
  static ALERT-SHUNT-OVER-VOLTAGE        ::= 0x8000
  static ALERT-SHUNT-UNDER-VOLTAGE       ::= 0x4000
  static ALERT-BUS-OVER-VOLTAGE          ::= 0x2000
  static ALERT-BUS-UNDER-VOLTAGE         ::= 0x1000
  static ALERT-POWER-OVER                ::= 0x0800
  static ALERT-CURRENT-OVER              ::= 0xFFFE
  static ALERT-CURRENT-UNDER             ::= 0xFFFF
  static ALERT-CONVERSION-READY          ::= 0x0400

  /** 
  Sampling options used for measurements. To be used with $set-sampling-rate
  */
  static AVERAGE-1-SAMPLE                ::= 0x0000 // Chip Default.
  static AVERAGE-4-SAMPLES               ::= 0x0001
  static AVERAGE-16-SAMPLES              ::= 0x0002
  static AVERAGE-64-SAMPLES              ::= 0x0003
  static AVERAGE-128-SAMPLES             ::= 0x0004
  static AVERAGE-256-SAMPLES             ::= 0x0005
  static AVERAGE-512-SAMPLES             ::= 0x0006
  static AVERAGE-1024-SAMPLES            ::= 0x0007

  /** 
  Bus and Shunt conversion timing options. To be used with $set-conversion-time
  */
  static TIMING-140-US                   ::= 0x0000
  static TIMING-204-US                   ::= 0x0001
  static TIMING-332-US                   ::= 0x0002
  static TIMING-588-US                   ::= 0x0003
  static TIMING-1100-US                  ::= 0x0004 // Chip Default.
  static TIMING-2100-US                  ::= 0x0005
  static TIMING-4200-US                  ::= 0x0006
  static TIMING-8300-US                  ::= 0x0007

  // Core Register Addresses.
  static REGISTER-CONFIG_                ::= 0x00  //RW  // All-register reset, shunt voltage and bus voltage ADC conversion times and averaging, operating mode.
  static REGISTER-SHUNT-VOLTAGE_         ::= 0x01  //R   // Shunt voltage measurement data.
  static REGISTER-BUS-VOLTAGE_           ::= 0x02  //R   // Bus voltage measurement data.
  static REGISTER-LOAD-POWER_            ::= 0x03  //R   // Value of the calculated power being delivered to the load.
  static REGISTER-SHUNT-CURRENT_         ::= 0x04  //R   // Value of the calculated current flowing through the shunt resistor.
  static REGISTER-CALIBRATION_           ::= 0x05  //RW  // Sets full-scale range and LSB of current and power measurements. Overall system calibration.
  static REGISTER-MASK-ENABLE_           ::= 0x06  //RW  // Alert configuration and Conversion Ready flag.
  static REGISTER-ALERT-LIMIT_           ::= 0x07  //RW  // Limit value to compare to the selected Alert function.
  static REGISTER-MANUF-ID_              ::= 0xFE  //R   // Contains unique manufacturer identification number.
  static REGISTER-DIE-ID_                ::= 0xFF  //R   // Contains unique die identification number.

  // Die & Manufacturer Info Masks (Masking REGISTER-DIE-ID_ register)
  static DIE-ID-RID-MASK_                ::= 0x000F // Masks its part of the REGISTER-DIE-ID Register.
  static DIE-ID-DID-MASK_                ::= 0xFFF0 // Masks its part of the REGISTER-DIE-ID Register.

  // Actual INA226 device ID - to identify this chip over INA3221 etc.
  static INA226-DEVICE-ID_               ::= 0x0226

  // Configuration Register bitmasks.
  static CONF-RESET-MASK_                ::= 0x8000
  static CONF-AVERAGE-MASK_              ::= 0x0E00
  static CONF-AVERAGE-OFFSET_            ::= 9
  static CONF-BUSVC-MASK_                ::= 0x01C0
  static CONF-BUSVC-OFFSET_              ::= 6
  static CONF-SHUNTVC-MASK_              ::= 0x0038
  static CONF-SHUNTVC-OFFSET_            ::= 3
  static CONF-MODE-MASK_                 ::= 0x0007
  static CONF-MODE-OFFSET_               ::= 0

  //  Get Alert Flag.
  static ALERT-CONVERSION-READY-FLAG_    ::= 0x0008
  static ALERT-CONVERSION-READY-OFFSET_  ::= 3
  static ALERT-CONVERSION-READY-LENGTH_  ::= 1
  static ALERT-FUNCTION-FLAG_            ::= 0x0010
  static ALERT-FUNCTION-OFFSET_          ::= 4
  static ALERT-FUNCTION-LENGTH_          ::= 1
  static ALERT-MATH-OVERFLOW-FLAG_       ::= 0x0004
  static ALERT-MATH-OVERFLOW-OFFSET_     ::= 2
  static ALERT-MATH-OVERFLOW-LENGTH_     ::= 1
  static ALERT-PIN-POLARITY-BIT_         ::= 0x0002
  static ALERT-PIN-POLARITY-OFFSET_      ::= 1
  static ALERT-PIN-POLARITY-LENGTH_      ::= 1
  static ALERT-LATCH-ENABLE-BIT_         ::= 0x0001
  static ALERT-LATCH-ENABLE-OFFSET_      ::= 0
  static ALERT-LATCH-ENABLE-LENGTH_      ::= 1
  static CONVERSION-READY-BIT_           ::= 0x0800
  static CONVERSION-READY-OFFSET_        ::= 11
  static CONVERSION-READY-LENGTH_        ::= 1

  static INTERNAL_SCALING_VALUE_/float            ::= 0.00512
  static ADC-FULL-SCALE-SHUNT-VOLTAGE-LIMIT/float ::= 0.08192  // volts.

  reg_/registers.Registers               := ?       // set by contsructor.
  logger_/log.Logger                     := ?       // set by contsructor.
  current-divider-ma_/float              := 0.0
  power-multiplier-mw_/float             := 0.0
  last-measure-mode_/int                 := MODE-CONTINUOUS
  current-LSB_/float                     := 0.0
  shunt-resistor_/float                  := 0.0
  current-range_/float                   := 0.0
  max-current_/float                     := 0.0
  
  constructor dev/serial.Device --logger/log.Logger=(log.default.with-name "ina226"):
    logger_ = logger
    reg_ = dev.registers

    if (read-device-identification != INA226-DEVICE-ID_): 
      logger_.info "Device is NOT an INA226 (0x$(%04x INA226-DEVICE-ID_) [Device ID:0x$(%04x read-device-identification)]) "
      logger_.info "Device is man-id=0x$(%04x read-manufacturer-id) dev-id=0x$(%04x read-device-identification) rev=0x$(%04x read-device-revision)"
      throw "Device is not an INA226."

    initialise-device_

  /** 
  Initial Device Configuration - Starts:
  - Assuming the default shunt resistor is installed R100 (0.1 Ohm).
  - Starts in Continuous Mode.

  The Current Register (04h) and Power Register (03h) default to '0' because the Calibration 
  register defaults to '0', yielding zero current and power values until the Calibration 
  register is programmed.  The setting of the resistor value writes the initial calibration 
  value, initial average value and conversion time.  Therefore, this constructor runs the 
  private method '$initialise-device_'.  If a different shunt resistor is used, this must be
  set directly after the object is instantiated.
  */
  initialise-device_ -> none:
    // Maybe not required but the manual suggests you should do it.
    reset_

    // Initialise Default sampling, conversion timing, and measuring mode.
    set-sampling-rate --rate=AVERAGE-1-SAMPLE
    set-conversion-time --bus=TIMING-1100-US     // Chip Default.  Shown here for clarity.
    set-conversion-time --shunt=TIMING-1100-US   // Chip Default.  Shown here for clarity.
    set-measure-mode --mode=MODE-CONTINUOUS

    // Set Defaults for Shunt Resistor - module usually ships with R100. (0.100 Ohm)
    set-shunt-resistor --resistor=0.100
    
    // Performing a single measurement during initialisation assists with accuracy for first reads.
    trigger-single-measurement
    wait-until-conversion-completed

  /** 
  $reset_: Reset Device.
  
  Setting bit 16 resets the device.  Once directly set, the bit self-clears afterwards.
  */
  reset_ -> none:
    old-value := reg_.read-u16-be REGISTER-CONFIG_
    new-value := old-value | CONF-RESET-MASK_
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    sleep --ms=(get-estimated-conversion-time-ms)
    after-value := reg_.read-u16-be REGISTER-CONFIG_
    //logger_.info "reset_: 0x$(%04x old-value) [to 0x$(%04x new-value)] - after reset 0x$(%04x after-value)"

  /** 
  $get-calibration-value: Gets current calibration value.
  
  the Calibration value scales the raw sensor data so that it corresponds to
  real-world values, taking into account the shunt resistor value, the full-scale range, and 
  other system-specific factors. This value is caluclated automatically by the $set-shunt-resistor 
  method - setting manually is not normally required.  See Datasheet pp.10.
  */
  get-calibration-value -> int:
    return reg_.read-u16-be REGISTER-CALIBRATION_

  /**
  $set-calibration-value: Sets calibration value.  
  
  the Calibration value scales the raw sensor data so that it corresponds to real-world values, 
  taking into account the shunt resistor value, the full-scale range, and other system-specific
  factors. This value is caluclated automatically by the $set-shunt-resistor method - setting
  manually is not normally required.  See Datasheet pp.10.
  */
  set-calibration-value --value/int -> none:
    old-value := reg_.read-u16-be REGISTER-CALIBRATION_
    reg_.write-u16-be REGISTER-CALIBRATION_ value
    logger_.debug "calibration-value: changed from $(old-value) to $(value)"

  /** 
  $set-sampling-rate --rate: Adjust Sampling Rate for measurements.  
  
  The sampling rate determines how often the device samples and averages the input 
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.  This is the register code/enum value, not actual rate. Can be
  converted back using  $get-sampling-rate --count={enum}
  */
  set-sampling-rate --rate/int -> none:
    old-value/int  := reg_.read-u16-be REGISTER-CONFIG_
    new-value/int  := old-value
    new-value      &= ~(CONF-AVERAGE-MASK_)
    new-value      |= (rate << 9)
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    logger_.debug "sampling-rate: set from 0x$(%02x old-value) to 0x$(%02x new-value)"

  /**
  $get-sampling-rate --code: Retrieve current sampling rate selector/enum.
  
  The sampling rate determines how often the device samples and averages the input 
  signals (bus voltage and shunt voltage) before storing them in the result registers.
  More samples lead to more stable values, but can lengthen the time required for a
  single measurement.
  */
  get-sampling-rate --code -> int:
    return ((reg_.read-u16-be REGISTER-CONFIG_ & CONF-AVERAGE-MASK_) >> 9)

  /** $get-sampling-rate --count: Return human readable sampling count number. */
  get-sampling-rate --count -> int:
    return get-sampling-rate-from-enum --code=(get-sampling-rate --code)

  /**
  Conversion Time:  The time spent by the ADC on a single measurement. 
  
  Individual values are set for either the shunt or the bus voltage.
  - Longer time = more samples averaged inside = less noise, higher resolution.
  - Shorter time = fewer samples = faster updates, but noisier.
  Both Bus and Shunt have separate conversion times
  - Bus voltage = the “supply” or “load node” you’re monitoring.
  - Shunt voltage = the tiny drop across your shunt resistor.
  - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt.
  */

  /**
  $set-conversion-time --bus: Sets conversion-time for bus only. See 'Conversion Time'.
  */  
  set-conversion-time --bus/int -> none:
    old-value/int := reg_.read-u16-be REGISTER-CONFIG_
    new-value/int := old-value
    new-value     &= ~CONF-BUSVC-MASK_
    new-value     |= (bus << CONF-BUSVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    logger_.debug "conversion-time: --bus REGISTER-CONFIG_ set from 0x$(%02x old-value) to 0x$(%02x new-value)"

  /**
  $set-conversion-time --shunt: Sets conversion-time for shunt only. See 'Conversion Time'.
  */  
  set-conversion-time --shunt/int -> none:
    old-value/int := reg_.read-u16-be REGISTER-CONFIG_
    new-value/int := old-value
    new-value     &= ~CONF-SHUNTVC-MASK_
    new-value     |= (shunt << CONF-SHUNTVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    logger_.debug "conversion-time: --shunt REGISTER-CONFIG_ set from 0x$(%02x old-value) to 0x$(%02x new-value)"

  /** 
  $set-measure-mode: Sets Measure Mode. 
  
  One of INA226-MODE-POWER-DOWN, INA226-MODE-TRIGGERED or INA226-MODE-CONTINUOUS.  Keeps track
  of last measure mode set, in a local variable, to ensures device comes back on into the 
  same previous mode when using 'power-on' and power-off functions.

  Mode         | Typical Supply Current | Description
  -------------|------------------------|------------------------------------------------------
  Power-Down   | 0.1 uA (typ)	        | Device is essentially off, no conversions occur.
  -------------|------------------------|------------------------------------------------------
  Triggered    | appx 330 uA per        | Device wakes up, performs one measurement (shunt or bus
               | conversion             | or both), then returns to power-down.
  -------------|------------------------|------------------------------------------------------
  Continuous   | appx 420 uA (typ)	    | Device continuously measures shunt and/or bus voltages.

  See section 6.6 of the Datasheet 'Electrical Characteristics'.
  */
  set-measure-mode --mode/int -> none:
    old-value/int := reg_.read-u16-be REGISTER-CONFIG_
    new-value/int := old-value
    new-value     &= ~(CONF-MODE-MASK_)
    new-value     |= mode                 // low value, no left shift offset.
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    if (mode != MODE-POWER-DOWN): last-measure-mode_ = mode

  /**
  $set-power-off: simple alias for disabling device.
  */
  set-power-off -> none:
    set-measure-mode --mode=MODE-POWER-DOWN

  /**
  $set-power-on: simple alias for enabling the device.

  Resets to the last mode set by $set-measure-mode.
  */
  set-power-on -> none:
    set-measure-mode --mode=last-measure-mode_
    sleep --ms=(get-estimated-conversion-time-ms)

  /**
  $set-shunt-resistor --resistor --max-current: Set resistor and current range.
  
  Resistor value in ohm, Current range in amps.
  */
  set-shunt-resistor --resistor/float --max-current/float -> none:
    shunt-resistor_        = resistor                                              // Cache to class-wide for later use.
    max-current_           = max-current                                           // Cache to class-wide for later use.
    current-LSB_           = (max-current_ / 32768.0)                              // Amps per bit (eg. LSB).
    //logger_.debug "shunt-resistor: current per bit = $(current-LSB_)A"
    new-calibration-value := INTERNAL_SCALING_VALUE_ / (current-LSB_ * resistor)
    //logger_.debug "shunt-resistor: calibration value becomes = $(new-calibration-value) $((new-calibration-value).round)[rounded]"
    set-calibration-value --value=(new-calibration-value).round
    current-divider-ma_    = 0.001 / current-LSB_
    power-multiplier-mw_   = 1000.0 * 25.0 * current-LSB_
    logger_.debug "shunt-resistor: (32767 * current-LSB_)=$(32767 * current-LSB_) compared to $(max-current_)"

  /**
  $set-shunt-resistor --resistor: 
  
  Set shunt resistor value manually, assuming maximum current. Resistor value input is in Ohms.
  The max current is computed from +/-81.92 mV full scale.
  */
  set-shunt-resistor --resistor/float -> none:
    // Current range - max measurable current given the shunt resistor.
    current-max/float := ADC-FULL-SCALE-SHUNT-VOLTAGE-LIMIT/resistor
    set-shunt-resistor --resistor=resistor --max-current=current-max

  /**
  $read-shunt-current: Return shunt current in amps. 
    
  The INA226 doesn't measure current directly—it measures the voltage drop across this shunt resistor
  and calculates current using Ohm’s Law.
  */ 
  read-shunt-current -> float:
    value   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    return (value * current-LSB_)

  /** 
  $read-shunt-voltage: Return shunt voltage in volts.
  
  The shunt voltage is the voltage drop across the shunt resistor, which allows the INA226 to calculate
  current. The INA226 measures this voltage to calculate the current flowing through the load.
  */   
  read-shunt-voltage -> float:
    value := reg_.read-i16-be REGISTER-SHUNT-VOLTAGE_
    return (value * 0.0000025)

  /**
  $read-supply-voltage --volts: Upstream voltage, before the shunt (IN+).
  
  This is the rail straight from the power source, minus any drop across the shunt. Since INA226 
  doesn’t have a dedicated pin for this, it can be reconstructed by: Vsupply = Vbus + Vshunt.   
  i.e. adding the measured bus voltage (load side) and the measured shunt voltage.
  */
  read-supply-voltage -> float:
    return read-bus-voltage + read-shunt-voltage

  /**
  $read-bus-voltage --volts: whatever is wired to the VBUS pin.  

  On most breakout boards, VBUS is tied internally to IN− (the low side of the shunt). So in 
  practice, “bus voltage” usually means the voltage at the load side of the shunt.  This is
  what the load actually sees as its supply rail.
  */
  read-bus-voltage -> float:
    value := reg_.read-i16-be REGISTER-BUS-VOLTAGE_
    return (value * 0.00125)
  
  /**
  $read-load-power: Watts used by the load.
  
  Calculated using the cached multiplier: [power-multiplier-mw_ = 1000 * 25 * current-LSB_]
  */
  read-load-power -> float:
    value := reg_.read-u16-be REGISTER-LOAD-POWER_
    return ((value * power-multiplier-mw_).to-float / 1000.0)

  /** 
  $busy: Returns true if conversion is still ongoing 
  
  Register MASK-ENABLE is read each poll.  In practices it does return the pre-clear CNVR
  bit, but reading also clears it. Loops using `while busy` will work (eg. false when 
  flag is 1), but it does mean a single poll will consume the flag. (This is already compensated
  for with the loop in 'wait-until-' functions'.)
  */
  busy -> bool:
    value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_              // Reading clears CNVR (Conversion Ready) Flag.
    return ((value & ALERT-CONVERSION-READY-FLAG_) == 0)

  /**
  $wait-until-conversion-completed: execution blocked until conversion is completed.
  */
  wait-until-conversion-completed -> none:
    max-wait-time-ms/int   := get-estimated-conversion-time-ms
    current-wait-time-ms/int   := 0
    sleep-interval-ms/int := 50
    while busy:                                                      // Checks if sampling is completed.
      sleep --ms=sleep-interval-ms
      current-wait-time-ms += sleep-interval-ms
      if current-wait-time-ms >= max-wait-time-ms:
        logger_.debug "wait-until-conversion-completed: maxWaitTime $(max-wait-time-ms)ms exceeded - breaking"
        break

  /**
  $trigger-single-measurement: initiate a single measurement without waiting for completion.
  */
  trigger-single-measurement -> none:
    trigger-single-measurement --nowait
    wait-until-conversion-completed
  
  /** 
  $trigger-single-measurement: perform a single conversion - without waiting.
  */
  trigger-single-measurement --nowait -> none:
    mask-register-value/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_        // Reading clears CNVR (Conversion Ready) Flag.
    config-register-value/int   := reg_.read-u16-be REGISTER-CONFIG_     
    reg_.write-u16-be REGISTER-CONFIG_ config-register-value                   // Starts conversion.

  /** 
  $set-alert: configures the various alert types.

  Requires a value from the alert type enum.  If multiple functions are enabled the highest 
  significant bit position Alert Function (D15-D11) takes priority and responds to the Alert
  Limit Register.  ie. only one alert of one type can be configured simultaneously.  Whatever
  is in the alert value (register) at that time, is then the alert trigger value.

  Limits must be supplied in base SI units (volts, amps and watts) only.
  */
  set-alert --type/int --limit/float -> none:
    alert-limit/float := 0.0

    if type == ALERT-SHUNT-OVER-VOLTAGE:             // Alert limit in VOLTS.
      alert-limit = limit * 400000.0          
    else if type == ALERT-SHUNT-UNDER-VOLTAGE:       // Alert limit in VOLTS.
      alert-limit = limit * 400000.0
    else if type == ALERT-CURRENT-OVER:
      type = ALERT-SHUNT-OVER-VOLTAGE
      alert-limit = limit * shunt-resistor_ * 400000.0
    else if type == ALERT-CURRENT-UNDER:
      type = ALERT-SHUNT-UNDER-VOLTAGE
      alert-limit = limit * shunt-resistor_ * 400000.0
    else if type == ALERT-BUS-OVER-VOLTAGE:          // limit is in volts (1.25 mV / LSB ⇒ 800 counts per volt)
      alert-limit = limit * 800.0
    else if type == ALERT-BUS-UNDER-VOLTAGE:         // limit is in volts (1.25 mV / LSB ⇒ 800 counts per volt)
      alert-limit = limit * 800.0
    else if type == ALERT-POWER-OVER:
      alert-limit = limit / power-multiplier-mw_
    else:
      logger_.debug "set-alert: unexpected alert type"
      throw "set-alert: unexpected alert type"
    
    // Set Alert Type Flag.
    old-value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    new-value/int := old-value
    new-value     &= ~(0xF800)    // Clear old alert values (bits D11 to D15) - only one alert allowed at once.
    new-value     |= type         // Already bit shifted in the mask constants!
    reg_.write-u16-be REGISTER-MASK-ENABLE_ new-value
    logger_.debug "set-alert: mask $(bits-16 old-value) to $(bits-16 new-value)"

    // Set Alert Limit Value
    reg_.write-u16-be REGISTER-ALERT-LIMIT_ (alert-limit).to-int
    logger_.debug "set-alert: alert limit set to $(alert-limit)"

  /** 
  $set-alert-latch: "Latching".
  
  When the Alert Latch Enable bit is set to Transparent mode, the Alert pin and Flag bit 
  resets to the idle states when the fault has been cleared.  When the Alert Latch Enable bit
  is set to Latch mode, the Alert pin and Alert Flag bit remains active following a fault 
  until the Mask/Enable Register has been read.
  - 1 = Latch enabled
  - 0 = Transparent (default)
  */
  set-alert-latch --set/int -> none:
    assert: 0 <= set <= 1
    old-value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    new-value/int := old-value
    new-value     &= ~(ALERT-LATCH-ENABLE-BIT_)
    new-value     |= (set << ALERT-LATCH-ENABLE-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ new-value
    logger_.debug "alert-latch alert-pin $(set) is $(bits-16 old-value) to $(bits-16 new-value)"

  /** 
  $get-alert-latch: Retrieve Latch Configuration.
  */
  get-alert-latch -> int:
    value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    latchBit/int := ((value & ALERT-LATCH-ENABLE-BIT_) >> ALERT-LATCH-ENABLE-OFFSET_) & ALERT-LATCH-ENABLE-LENGTH_
    return latchBit
  
  /** 
  $set-alert-pin-polarity: Alert pin polarity functions.
  
  Settings:
  - 1 = Inverted (active-high open collector).
  - 0 = Normal (active-low open collector) (default).
  */
  set-alert-pin-polarity --set/int -> none:
    assert: 0 <= set <= 1
    old-value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    new-value/int := old-value
    new-value     &= ~(ALERT-PIN-POLARITY-BIT_)
    new-value     |= (set << ALERT-PIN-POLARITY-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ new-value
    logger_.debug "alert-pin-polarity: alert-pin $(set) is $(bits-16 old-value) to $(bits-16 new-value)"

  /** 
  $get-alert-pin-polarity: Retrieve configured alert pin polarity setting. See '$set-alert-pin-polarity'.
  */
  get-alert-pin-polarity -> int:
    // inverted = true, normal = false
    value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    polarityInvertedBit/int := ((value & ALERT-PIN-POLARITY-BIT_) >> ALERT-PIN-POLARITY-OFFSET_) & ALERT-PIN-POLARITY-LENGTH_
    logger_.debug "alert-pin-polarity: is $(polarityInvertedBit)"
    return polarityInvertedBit

  /** 
  $alert: return true if any of the three alerts exists.

  Slightly different to other implementations. This method attempts to keep alerts visible 
  as a value on the class object, so as not to be stored separately from the source of truth
  and therefore risk being stale.  So these functions attempt to source the current status 
  of each alert from the device itself.
  */
  alert -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    if (register & ALERT-MATH-OVERFLOW-FLAG_) != 0: logger_.debug "alert: ALERT-MATH-OVERFLOW-FLAG_"
    if (register & ALERT-FUNCTION-FLAG_) != 0: logger_.debug "alert: ALERT-FUNCTION-FLAG_"
    if (register & ALERT-CONVERSION-READY-FLAG_) != 0: logger_.debug "alert: ALERT-CONVERSION-READY-FLAG_"
    checkMask    := ALERT-MATH-OVERFLOW-FLAG_ | ALERT-FUNCTION-FLAG_ | ALERT-CONVERSION-READY-FLAG_
    return (register & checkMask) != 0

  /**
  $clear-alert: clears alerts.
  
  Test well when used: datasheet suggests simply reading the MASK-ENABLE is enough to clear any alerts.
  */
  clear-alert -> none:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_

  /** 
  $overflow-alert: returns true if an overflow alert exists.
  */
  overflow-alert  -> bool:
    value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    overflow/bool := false
    overflow-bit := ((value & ALERT-MATH-OVERFLOW-FLAG_) >> ALERT-MATH-OVERFLOW-OFFSET_ ) & ALERT-MATH-OVERFLOW-LENGTH_
    if overflow-bit == 1: overflow = true
    logger_.debug "alert --overflow: overflow bit is $(overflow-bit) [$(overflow)]"
    return overflow

  /** 
  $limit-alert: returns true if a set alert limit is exceeded.
  */
  limit-alert  -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    limit := false
    limit-bit := ((register & ALERT-FUNCTION-FLAG_) >> ALERT-FUNCTION-OFFSET_ ) & ALERT-FUNCTION-LENGTH_
    if limit-bit == 1: limit = true
    logger_.debug "limit-alert: configured limit bit is $(limit-bit) [$(limit)]"
    return limit

  /** 
  $conversion-ready-alert: Determine If conversion is complete.
  
  Although the device can be read at any time, and the data from the last conversion
  is available, the Conversion Ready Flag bit is provided to help coordinate one-shot
  or triggered conversions. The Conversion Ready Flag bit is set after all conversions,
  averaging, and multiplications are complete. Conversion Ready Flag bit clears under
  the following conditions:
      1. Writing to the Configuration Register (except for Power-Down selection).
      2. Reading the Mask/Enable Register (Implemented in $clear-alert).
  */
  conversion-ready-alert -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    conversion-ready := false
    conversion-ready-bit := ((register & ALERT-CONVERSION-READY-FLAG_) >> ALERT-CONVERSION-READY-OFFSET_ ) & ALERT-CONVERSION-READY-LENGTH_
    if conversion-ready-bit == 1: conversion-ready = true
    logger_.debug "conversion-ready-alert: conversion ready bit is $(conversion-ready-bit) [$(conversion-ready)]"
    return conversion-ready

  /** 
  $is-conversion-ready: alias returning true/false for $conversion-ready-alert.
  */
  is-conversion-ready -> bool:
    return conversion-ready-alert
  
  /** 
  $set-conversion-ready --set/int: Configure the alert function enabling the pin to
  be used to signal conversion ready.
  */
  set-conversion-ready --set/int -> none:
    assert: 0 <= set <= 1
    old-value/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    new-value/int := old-value
    new-value     &= ~(CONVERSION-READY-BIT_)
    new-value     |= (set << CONVERSION-READY-OFFSET_) // Already bit shifted.
    reg_.write-u16-be REGISTER-MASK-ENABLE_ new-value
    logger_.debug "conversion-ready: alert-pin $(set) is $(bits-16 old-value) to $(bits-16 new-value)"

  /** 
  $set-conversion-ready --enable-alert-pin: Helpful alias for setting 'conversion-ready' on alert pin.
  */
  set-conversion-ready --enable-alert-pin -> none:
    set-conversion-ready --set=1

  /** 
  $set-conversion-ready --disable-alert-pin: Helpful alias for setting 'conversion-ready' on alert pin.
  */
  set-conversion-ready --disable-alert-pin -> none:
    set-conversion-ready --set=0

  /**
  $get-conversion-time-us-from-enum: Returns microsecs for TIMING-x-US statics 0..7 (values as stored in the register).
  */
  get-conversion-time-us-from-enum --code/int -> int:
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
  $get-sampling-rate-from-enum: Returns sample count for AVERAGE-x-SAMPLE statics 0..7 (values as stored in the register).
  */
  get-sampling-rate-from-enum --code/int -> int:
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
  $get-estimated-conversion-time-ms: estimate a worst-case maximum waiting time based on the configuration.
  
  Done this way to prevent setting a global maxWait type value, to then have it fail based
  on times that are longer due to timing configurations.  Calculation also includes a 10% guard.
  */
  get-estimated-conversion-time-ms -> int:
    // Read config and decode fields using masks/offsets
    config-reg-value/int              := reg_.read-u16-be REGISTER-CONFIG_

    samples-code/int                  := (config-reg-value & CONF-AVERAGE-MASK_)  >> CONF-AVERAGE-OFFSET_
    bus-conversion-time-code/int      := (config-reg-value & CONF-BUSVC-MASK_)    >> CONF-BUSVC-OFFSET_
    shunt-conversion-time-code/int    := (config-reg-value & CONF-SHUNTVC-MASK_)  >> CONF-SHUNTVC-OFFSET_
    mode/int                          := (config-reg-value & CONF-MODE-MASK_)     >> CONF-MODE-OFFSET_

    sampling-rate/int                 := get-sampling-rate-from-enum --code=samples-code
    bus-conversion-time/int           := get-conversion-time-us-from-enum --code=bus-conversion-time-code
    shunt-conversion-time/int         := get-conversion-time-us-from-enum --code=shunt-conversion-time-code

    // Mode 0x7 = bus+shunt continuous, 0x3 = bus+shunt triggered (single-shot).
    // If converting to support bus-only or shunt-only modes, drop the other term.
    totalus/int    := (bus-conversion-time + shunt-conversion-time) * sampling-rate

    // Add a small guard factor (~10%) to be conservative.
    totalus = ((totalus * 11.0) / 10.0).to-int

    // Return milliseconds, minimum 1 ms
    totalms := ((totalus + 999) / 1000).to-int  // Ceiling.
    if totalms < 1: totalms = 1

    //logger_.debug "get-estimated-conversion-time-ms is: $(totalms)ms"
    return totalms

  /** 
  $read-manufacturer-id: Get Manufacturer identifier.
  
  Useful if expanding driver to suit an additional sibling devices.
  */
  read-manufacturer-id -> int:
    manid := reg_.read-u16-be REGISTER-MANUF-ID_
    //logger_.debug "manufacturer-id: is 0x$(%04x manid) [$(manid)]"
    return manid
  
  /** 
  $read-device-identification: returns integer of device ID bits from register.
  
  Bits 4-15 Stores the device identification bits.
  */
  read-device-identification -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    die-id-device-id := (register & DIE-ID-DID-MASK_) >> 4
    //logger_.debug "device-identification: is 0x$(%04x dieidDid) [$(dieidDid)]"
    return die-id-device-id

  /** 
  $read-device-revision: Die Revision ID Bits.
  
  Bits 0-3 store the device revision number bits.
  */
  read-device-revision -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    die-id-revision-id := (register & DIE-ID-RID-MASK_)
    //logger_.debug "device-revision: is 0x$(%04x dieidRid) [$(dieidRid)]"
    return die-id-revision-id

  /** 
  $infer-shunt-resistor: Infer Shunt Resistor using a known load resistor.
  
  Averages a few samples for stability, ensures both voltages come from the same
  conversion, and returns the estimated shunt value.
  
  On Accuracy:
  - Known load tolerance dominates: use a 0.1–1% resistor if possible.
  - Make sure VBUS & load node (IN−) are tied.
  - Kelvin the shunt if possible: sense pins at the shunt pads.
  - Perform test/readings after the load settles - average some samples.
  - Low-current corner: if Vshunt is just a few tens of µV, quantization/noise can
    move the estimate; use a load that draws a few mA+ to get a clean mV-level Vsh.
  */
  infer-shunt-resistor --load-resistor/float -> float:
    assert: load-resistor > 0.0

    // Make sure we read one coherent conversion.
    trigger-single-measurement
    wait-until-conversion-completed

    // Light Averaging
    load-voltage-sum/float       := 0.0
    shunt-voltage-sum/float      := 0.0
    samples/int                  := 8
    samples.repeat:
      load-voltage-sum           += read-bus-voltage
      shunt-voltage-sum          += read-shunt-voltage

    // Replace values with calculated average.
    load-voltage/float          := load-voltage-sum / samples.to-float
    shunt-voltage/float         := shunt-voltage-sum / samples.to-float

    // Estimate current via Ohm's law on the known load.
    current-estimate/float := load-voltage / load-resistor
    assert: current-estimate > 0.0

    shunt-resistor-estimate/float := shunt-voltage / current-estimate
    logger_.debug "infer-shunt-resistor: Vload=$(load-voltage) V  Vsh=$(shunt-voltage) V  Rload=$(load-resistor) Ohm  -> I=$(current-estimate)A  Rsh_est=$(shunt-resistor-estimate) Ohm"
    return shunt-resistor-estimate

  /**
  $infer-shunt-resistor --loadCurrent: Determine shunt resistor value from known load.

  Useful if you have a DMM clamp or source.  See notes above for similar function.
  */
  infer-shunt-resistor --load-current/float -> float:
    assert: load-current > 0.0

    // Make sure we read one coherent conversion.
    trigger-single-measurement
    wait-until-conversion-completed
    
    // take some samples and average the shuntVoltage a bit.
    shunt-voltage-sum/float      := 0.0
    samples/int                  := 8
    samples.repeat:
      shunt-voltage-sum += read-shunt-voltage
      
    shunt-voltage/float          := shunt-voltage-sum / samples.to-float
    shunt-resistor-estimate/float := shunt-voltage / load-current
    logger_.debug "infer-shunt-resistor: Vsh=$(shunt-voltage)V  I_known=$(load-current)A  -> Rsh_est=$(shunt-resistor-estimate)Ω"
    return shunt-resistor-estimate

  /** 
  $print-diagnostics: Print Diagnostic Information.
  
  Prints relevant measurement information allowing someone with a Voltmeter to double 
  check what is measured and compare it.  Also calculates/compares using Ohms Law (V=I*R).
  */
  print-diagnostics -> none:
    // Optional: ensure fresh data.
    trigger-single-measurement
    wait-until-conversion-completed

    shunt-voltage/float                := read-shunt-voltage
    load-voltage/float                 := read-bus-voltage                   // what the load actually sees (Vbus, eg IN−).
    supply-voltage/float               := load-voltage + shunt-voltage       // upstream rail (IN+ = IN− + Vshunt).
    shunt-voltage-delta/float          := supply-voltage - load-voltage      // same as Vshunt.
    shunt-voltage-delta-percent/float  := 0.0
    if supply-voltage > 0.0: shunt-voltage-delta-percent = (shunt-voltage-delta / supply-voltage) * 100.0

    calibration-value/int            := get-calibration-value
    current-raw/int                  := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    least-significant-bit/float      := 0.00512 / (calibration-value.to-float * shunt-resistor_)
    current-chip/float               := current-raw * least-significant-bit
    current-v-r/float                := shunt-voltage / shunt-resistor_

    // CROSSCHECK: between chip/measured current and V/R reconstructed current.
    current-difference/float         := (current-chip - current-v-r).abs
    current-difference-percent/float := 0.0
    if (current-v-r != 0.0): 
      current-difference-percent      = (current-difference / current-v-r) * 100.0

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
  $bits-16: Displays bitmasks nicely when testing.
  */
  bits-16 x/int --display-bits/int=8 -> string:
    if (x > 255) or (display-bits > 8):
      out-string := "$(%b x)"
      out-string = out-string.pad --left 16 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8]).$(out-string[8..12]).$(out-string[12..16])"
      return out-string
    else:
      out-string := "$(%b x)"
      out-string = out-string.pad --left 8 '0'
      out-string = "$(out-string[0..4]).$(out-string[4..8])"
      return out-string
