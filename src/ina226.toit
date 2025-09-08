// Copyright (C) 2025 Ian
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import binary
import serial.device as serial
import serial.registers as registers



// DEFAULT-I2C-ADDRESS is 64 with jumper defaults.
// Valid address values: 64 to 79 - See datasheet table 6-2
DEFAULT-I2C-ADDRESS                      ::= 0x40

// Constants to be used by users during configuration

// Alert Types that can set off the alert register and/or alert pin.
ALERT-SHUNT-OVER-VOLTAGE                 ::= 0x8000
ALERT-SHUNT-UNDER-VOLTAGE                ::= 0x4000
ALERT-BUS-OVER-VOLTAGE                   ::= 0x2000
ALERT-BUS-UNDER-VOLTAGE                  ::= 0x1000
ALERT-POWER-OVER                         ::= 0x0800
ALERT-CURRENT-OVER                       ::= 0xFFFE
ALERT-CURRENT-UNDER                      ::= 0xFFFF
ALERT-CONVERSION-READY                   ::= 0x0400

// AVERAGE SAMPLE SIZE ENUM 
AVERAGE-1-SAMPLE                         ::= 0x0000 // Chip Default
AVERAGE-4-SAMPLES                        ::= 0x0001
AVERAGE-16-SAMPLES                       ::= 0x0002
AVERAGE-64-SAMPLES                       ::= 0x0003
AVERAGE-128-SAMPLES                      ::= 0x0004
AVERAGE-256-SAMPLES                      ::= 0x0005
AVERAGE-512-SAMPLES                      ::= 0x0006
AVERAGE-1024-SAMPLES                     ::= 0x0007

// BVCT and SVCT conversion timing ENUM
TIMING-140-US                            ::= 0x0000
TIMING-204-US                            ::= 0x0001
TIMING-332-US                            ::= 0x0002
TIMING-588-US                            ::= 0x0003
TIMING-1100-US                           ::= 0x0004 // Default
TIMING-2100-US                           ::= 0x0005
TIMING-4200-US                           ::= 0x0006
TIMING-8300-US                           ::= 0x0007

// 'Measure Mode' (includes OFF)
MODE-POWER-DOWN                          ::= 0x0000
MODE-TRIGGERED                           ::= 0x0003
MODE-CONTINUOUS                          ::= 0x0007

/**
Toit Driver Library for an INA226 module, DC Shunt current and power sensor.  Several common modules exist based on the TI INA226 chip, atasheet: https://www.ti.com/lit/ds/symlink/ina226.pdf  One example: https://esphome.io/components/sensor/ina226/ 
There are others with different feature sets and may be partially code compatible.

# Simplest Use Case
Simplest use case assumes an unmodified module with default wiring guidelines followed.  (Please see the Readme for pointers & guidance.) Assumes:
 - Module shunt resistor value R100 (0.1 Ohm)
 - Sample size of 1 (eg, no averaging)
 - Conversion time of 1100us
 - Continuous Mode
```
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
  
  # Continuously read and display values
  while true:
    print "$(%0.3f (ina226driver.load-current --amps))a"
    print "$(%0.2f (ina226driver.supply-voltage --volts))v"
    print "$(%0.4f (ina226driver.load-power --watts))w"
    sleep --ms=500
```

# Use Case: Measuring Very Small Currents
In this case the task is to measure tiny standby or sleep currents in the milliamp range.  The default shunt resistor is replaced with a larger value resistor (e.g. 1.0 Ω).  This increases the voltage drop per milliamp, giving the INA226 finer resolution for small loads. [The trade-off is that the maximum measurable current shrinks to about 80 mA (since the INA226 input saturates at ~81.92 mV), and more power is dissipated in the shunt as heat.]
```
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

```

# Use Case: Balancing Update Speed vs. Accuracy in a Battery-Powered Scenario
Where the module must be wired into a solution running on a battery. The INA226 is used to monitor the node’s power draw to be able to estimate battery life.  The driver runs in continuous conversion mode by default, sampling all the time at relatively short conversion times.  This has a higher power requirement as the INA226 is constantly awake and operating.  
In this case the driver needs to use triggered (single-shot) mode with longer conversion times and averaging enabled. 
```
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
```

*/

/** 

$DEFAULT-I2C-ADDRESS ($ hotlinks to code location!)  Used for parameters

*/



class Driver:
  // Core Register Addresses
  static REGISTER-CONFIG_                ::= 0x00  //RW  // All-register reset, shunt voltage and bus voltage ADC conversion times and averaging, operating mode.
  static REGISTER-SHUNT-VOLTAGE_         ::= 0x01  //R   // Shunt voltage measurement data
  static REGISTER-BUS-VOLTAGE_           ::= 0x02  //R   // Bus voltage measurement data
  static REGISTER-LOAD-POWER_            ::= 0x03  //R   // value of the calculated power being delivered to the load
  static REGISTER-SHUNT-CURRENT_         ::= 0x04  //R   // value of the calculated current flowing through the shunt resistor
  static REGISTER-CALIBRATION_           ::= 0x05  //RW  // Sets full-scale range and LSB of current and power measurements. Overall system calibration.
  static REGISTER-MASK-ENABLE_           ::= 0x06  //RW  // Alert configuration and Conversion Ready flag
  static REGISTER-ALERT-LIMIT_           ::= 0x07  //RW  // limit value to compare to the selected Alert function
  static REGISTER-MANUF-ID_              ::= 0xFE  //R   // Contains unique manufacturer identification number.
  static REGISTER-DIE-ID_                ::= 0xFF  //R   // Contains unique die identification number

  // Die & Manufacturer Info Masks
  static DIE-ID-RID-MASK_                ::= 0x000F // Masks its part of the REGISTER-DIE-ID Register
  static DIE-ID-DID-MASK_                ::= 0xFFF0 // Masks its part of the REGISTER-DIE-ID Register

  // Configuration Bitmasks
  static CONF-RESET-MASK_                ::= 0x8000
  static CONF-AVERAGE-MASK_              ::= 0x0E00
  static CONF-AVERAGE-OFFSET_            ::= 9
  static CONF-BUSVC-MASK_                ::= 0x01C0
  static CONF-BUSVC-OFFSET_              ::= 6
  static CONF-SHUNTVC-MASK_              ::= 0x0038
  static CONF-SHUNTVC-OFFSET_            ::= 3
  static CONF-MODE-MASK_                 ::= 0x0007
  static CONF-MODE-OFFSET_               ::= 0

  //  Get Alert Flag
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
  static CONVERSION-READY-OFFSET_        ::= 10
  static CONVERSION-READY-LENGTH_        ::= 1

  debug_/bool                            := false
  reg_/registers.Registers               := ?  
  current-divider-ma_/float              := 0.0
  power-multiplier-mw_/float             := 0.0
  last-measure-mode_/int                 := MODE-CONTINUOUS
  current-LSB_/float                     := 0.0
  shunt-resistor_/float                  := 0.0
  current-range_/float                   := 0.0
  correction-factor-a_/float             := 0.0

  constructor dev/serial.Device --debug/bool=false:
    reg_ = dev.registers
    initialise-device_
  
  debug-mode --enable -> none:
    debug_ = true

  debug-mode --disable -> none:
    debug_ = false

  // CONFIGURATION FUNCTIONS

  // Initial Device Configuration
  initialise-device_ -> none:
    reset_

    // NOTE:  Found an error by factor 100 and couldn't figure this out in any way
    //        left this hack (feature) in to allow a correction factor for values 
    //        match up with voltmeter. Before using the library, verify this value
    //        matches measurements IRL. 
    correction-factor-a_ = 100.0

    // NOTE:  The Current Register (04h) and Power Register (03h) default to '0' 
    //        because the Calibration register defaults to '0', yielding zero current
    //        and power values until the Calibration register is programmed.
    //        write initial calibration value, initial average value and conversion 
    //        time.  This is not done here to ensure resistor-range does this.
    // calibration-value --value=DEFAULT-CALIBRATION-VALUE

    // Initialise Default sampling, conversion timing, and measuring mode
    sampling-rate --rate=AVERAGE-1-SAMPLE
    conversion-time --time=TIMING-1100-US
    measure-mode --mode=MODE-CONTINUOUS

    // Set Defaults for Resistor Range
    // NOTE:  There appears to have been originally two constants/values for 'current range'
    //        MA_400 and MA_800 - I tested these and found that my voltmeter agreed when
    //        current range is set to 0.800a - eg 800ma.
    // NOTE:  Whilst not documented well for newbies like me, I assumed the resistor value
    //        needs to match the one on the board.  Mine is R100, which I assumed 0.1 Ohm.
    resistor-range --resistor=0.100 --current-range=0.8
    
    // NOTE:  Performing a single measurement here assists with accuracy for initial
    //        measurements.
    single-measurement
    wait-until-conversion-completed
    
    // NOTE:  Using this helper function, the actual values used in the calculations are visible
    if debug_: print-diagnostics

  // Reset Device
  // NOTE:  Setting bit 16 resets the device, afterwards the bit self-clears
  reset_ -> none:
    old-value := reg_.read-u16-be REGISTER-CONFIG_
    new-value := old-value | CONF-RESET-MASK_
    reg_.write-u16-be REGISTER-CONFIG_ new-value
    sleep --ms=(estimated-conversion-time --ms)
    if debug_:
       after-value := reg_.read-u16-be REGISTER-CONFIG_
       print "*      : reset - 0x$(%02x old-value) [to 0x$(%02x new-value)] - after reset 0x$(%02x after-value)"

  // Set Calibration Value 
  // NOTE:  Replaces calibration value outright
  calibration-value --value/int -> none:
    assert: ((value >= 1500) and (value <= 3000))  // sanity check
    old-value := reg_.read-u16-be REGISTER-CALIBRATION_
    reg_.write-u16-be REGISTER-CALIBRATION_ value
    if debug_: 
      print "*      : calibration-value         changed from $(old-value) to $(value)"
      checked-value/int := calibration-value
      print "*      : calibration-value CHECKED changed from $(old-value) to $(checked-value)"


  /** Get Calibration Value */
  calibration-value -> int:
    register := reg_.read-u16-be REGISTER-CALIBRATION_
    if debug_: print "*      : calibration-value retrieved $(register)"
    return register

  /** Adjust Calibration Value by Factor
  NOTE:  Retrieves and adjusted calibration value by a factor */
  calibration-value --factor/int -> none:
    oldCalibrationValue := calibration-value
    newCalibrationValue := oldCalibrationValue * factor
    calibration-value --value=newCalibrationValue
    if debug_: print "*      : calibration-value factor $(factor) adjusts from $(oldCalibrationValue) to $(newCalibrationValue)"

  /** Adjust Sampling Rate for measurements */
  sampling-rate --rate/int -> none:
    oldMask/int  := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int  := oldMask
    newMask      &= ~(CONF-AVERAGE-MASK_)
    newMask      |= (rate << 9)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    if debug_: print "*      : sampling-rate set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  /** Retrieve current sampling rate code/enum value */
  sampling-rate --code -> int:
    mask := reg_.read-u16-be REGISTER-CONFIG_
    return ((mask & CONF-AVERAGE-MASK_) >> 9)

  // Return human readable sampling count number
  // 
  sampling-rate --count -> int:
    return sampling-rate-from-enum --code=(sampling-rate --code)

  // Set Conversion Time
  // NOTE:  The conversion time setting tells the ADC how long to spend on a single 
  //        measurement of either the shunt voltage or the bus voltage.
  //        - Longer time = more samples averaged inside = less noise, higher resolution.
  //        - Shorter time = fewer samples = faster updates, but noisier.
  // NOTE:  Both Bus and Shunt have separate conversion times
  //        - Bus voltage = the “supply” or “load node” you’re monitoring.
  //        - Shunt voltage = the tiny drop across your shunt resistor.
  //        - Current isn’t measured directly — it’s computed later from Vshunt/Rshunt
  //
  conversion-time --bus/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~CONF-BUSVC-MASK_
    newMask     |= (bus << CONF-BUSVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    if debug_: print "*      : conversion-time --bus set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
  
  conversion-time --shunt/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~CONF-SHUNTVC-MASK_
    newMask     |= (shunt << CONF-SHUNTVC-OFFSET_)
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    if debug_: print "*      : conversion-time --shunt set from 0x$(%02x oldMask) to 0x$(%02x newMask)"

  // Sets both to the same when one value is given
  conversion-time --time/int -> none:
    conversion-time --shunt=time
    conversion-time --bus=time

  // Sets Measure Mode
  // NOTE:  Keeps track of last measure mode set, in a global. Ensures device comes back on
  //        into the same mode using 'PowerOn'
  measure-mode --mode/int -> none:
    oldMask/int := reg_.read-u16-be REGISTER-CONFIG_
    newMask/int := oldMask
    newMask     &= ~(CONF-MODE-MASK_)
    newMask     |= mode  //low value, no left shift offset
    reg_.write-u16-be REGISTER-CONFIG_ newMask
    if debug_: print "*      : measure-mode set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
    if (mode != MODE-POWER-DOWN): last-measure-mode_ = mode

  // Set resistor and current range, independently 
  // NOTE:  Resistor value in ohm, Current range in A
  // 
  resistor-range --resistor/float --current-range/float -> none:
    shunt-resistor_        = resistor                               // Cache to class-wide for later use
    current-range_         = current-range
    current-LSB_           = (current_range / 32768.0)     // A per bit (LSB)
    if debug_: print "*      : resistor-range: current per bit = $(current-LSB_)A"
    calibrationValue   := 0.00512 / (current-LSB_ * resistor)
    if debug_: print "*      : resistor-range: calibration value becomes = $(calibrationValue)"
    calibration-value --value=(calibrationValue).to-int
    current-divider_ma_    = 0.001 / current-LSB_
    power-multiplier_mw_   = 1000.0 * 25.0 * current-LSB_
    // TODO: Check for accuracy on the to-int

  resistor-range --resistor/float -> none:
    resistor-range --resistor=resistor --current-range=current-range_

  // MEASUREMENT FUNCTIONS

  shunt-current --amps -> float:
    register   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    return (register * current-LSB_ * correction-factor-a_)
  
  shunt-current --milliamps -> float:   return ((shunt-current --amps) * 1000.0)

  shunt-voltage --volts -> float:
    register := reg_.read-i16-be REGISTER-SHUNT-VOLTAGE_
    return (register * 0.0000025)

  shunt-voltage --millivolts -> float:  return (shunt-voltage --volts) * 1000.0
  
  // Upstream voltage, before the shunt (IN+).
  // NOTE:  That is the rail straight from the power source, minus any drop across
  //        the shunt. Since INA226 doesn’t have a dedicated pin for this, it can
  //        be reconstructed by: Vsupply = Vbus + Vshunt.   i.e. add the measured 
  //        bus voltage (load side) and the measured shunt voltage.
  supply-voltage --volts -> float:
    return ((bus-voltage --volts) + (shunt-voltage --volts))

  supply-voltage --millivolts -> float:
    return (supply-voltage --volts) * 1000.0

  bus-voltage --volts -> float:
    // whatever is wired to the VBUS pin.  On most breakout boards, VBUS is tied 
    // internally to IN− (the low side of the shunt). So in practice, “bus voltage” 
    // usually means the voltage at the load side of the shunt.  This is what the 
    // load actually sees as its supply rail.
    register := reg_.read-i16-be REGISTER-BUS-VOLTAGE_
    return (register * 0.00125)

  bus-voltage  --millivolts -> float:
    return (bus-voltage --volts) * 1000.0
  
  load-power --milliwatts -> float:
    // Using the cached multiplier [pwrMultiplier_mW_ = 1000 * 25 * current-LSB_]
    register := reg_.read-u16-be REGISTER-LOAD-POWER_
    return (register * power-multiplier-mw_).to-float

  load-power --watts -> float:
    return (load-power --milliwatts) / 1000.0

  // Aliases to help with user understanding of terms
  load-voltage --volts -> float:       return (bus-voltage --volts)
  load-voltage --millivolts -> float:  return (bus-voltage --volts) * 1000.0
  load-current --amps -> float:        return (shunt-current --amps)
  load-current --milliamps -> float:   return (shunt-current --milliamps)

  // Simple aliases for enabling and disabling device 
  // NOTE:  The powering on relies on the cached global variable which
  //        records what it was last set to.
  power-down -> none:
    measure-mode --mode=MODE-POWER-DOWN
  power-up -> none:
    measure-mode --mode=last-measure-mode_
    sleep --ms=(estimated-conversion-time --ms)

  // Returns true if conversion is still ongoing
  busy -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_            // clears CNVR (Conversion Ready) Flag
    val/bool     :=  ((register & ALERT-CONVERSION-READY-FLAG_) == 0)
    // if debug_: print "*      : busy compares  reg:val                              $(bits-16 register) to $(bits-16 ALERT-CONVERSION-READY-FLAG)"
    // if debug_: print "*      : busy returns $(val)"
    return val

  wait-until-conversion-completed -> none:
    maxWaitTimeMs/int   := estimated-conversion-time --ms
    curWaitTimeMs/int   := 0
    sleepIntervalMs/int := 50
    while busy:                                                               // checks if sampling is completed
        // if debug_: print "*      : waitUntilConversionCompleted waiting $(curWaitTimeMs)ms of max $(maxWaitTimeMs)ms"
        sleep --ms=sleepIntervalMs
        curWaitTimeMs += sleepIntervalMs
        if curWaitTimeMs >= maxWaitTimeMs:
          if debug_: print "*      : waitUntilConversionCompleted maxWaitTime $(maxWaitTimeMs)ms exceeded - breaking"
          break
    if debug_: print "*      : waitUntilConversionCompleted waited $(curWaitTimeMs)ms of max $(maxWaitTimeMs)ms"

  // Single Measurement - wait for completion
  //
  single-measurement -> none:
    single-measurement --nowait
    wait-until-conversion-completed
  
  // Perform a single conversion - without waiting
  //
  single-measurement --nowait -> none:
    maskRegister/int   := reg_.read-u16-be REGISTER-MASK-ENABLE_      // clears CNVR (Conversion Ready) Flag
    confRegister/int   := reg_.read-u16-be REGISTER-CONFIG_     
    reg_.write-u16-be REGISTER-CONFIG_ confRegister                   // Starts conversion

  // ALERT FUNCTIONS 

  // Configuring the various alert types
  // NOTE:  Requires a value from the alert type enum.  If multiple functions are enabled
  //        the highest significant bit position Alert Function (D15-D11) takes priority 
  //        and responds to the Alert Limit Register.  ie. only one alert of one type
  //        can be configured simultaneously.  Whatever is in the alert value (register) 
  //        at that time, is then the alert trigger value.
  //
  set-alert --type/int --limit/float -> none:
    alertLimit/float := 0.0

    if type == ALERT-SHUNT-OVER-VOLTAGE:
      alertLimit = limit * 400          
    else if type == ALERT-SHUNT-UNDER-VOLTAGE:
      alertLimit = limit * 400
    else if type == ALERT-CURRENT-OVER:
      type = ALERT-SHUNT-OVER-VOLTAGE
      alertLimit = limit * 2048 * current-divider-ma_ / (calibration-value).to-float
    else if type == ALERT-CURRENT-UNDER:
      type = ALERT-SHUNT-UNDER-VOLTAGE
      alertLimit = limit * 2048 * current-divider-ma_ / (calibration-value).to-float
    else if type == ALERT-BUS-OVER-VOLTAGE:
      alertLimit = limit * 800
    else if type == ALERT-BUS-UNDER-VOLTAGE:
      alertLimit = limit * 800
    else if type == ALERT-POWER-OVER:
      alertLimit = limit / power-multiplier-mw_
    else:
      if debug_: print "*      : set-alert unexpected alert type"
      throw "set-alert unexpected alert type"
    
    // Set Alert Type Flag
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(0xF800)    // clear old alert values (bits D11 to D15) - only one alert allowed at once
    newMask     |= type         // already bit shifted in the mask constants!
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    // if debug_: print "*      : set-alert mask set from 0x$(%02x oldMask) to 0x$(%02x newMask)"
    if debug_: print "*      : set-alert mask                                      $(bits-16 oldMask) to $(bits-16 newMask)"

    // Set Alert Limit Value
    reg_.write-u16-be REGISTER-ALERT-LIMIT_ (alertLimit).to-int
    if debug_: print "*      : set-alert alert limit set to $(alertLimit)"

  // Alert "Latching"
  // NOTE:  When the Alert Latch Enable bit is set to Transparent mode, the Alert 
  //        pin and Flag bit resets to the idle states when the fault has been cleared.
  //        When the Alert Latch Enable bit is set to Latch mode, the Alert pin and
  //        Alert Flag bit remains active following a fault until the Mask/Enable 
  //        Register has been read.
  //        1 = Latch enabled
  //        0 = Transparent (default)
  //
  alert-latch --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(ALERT-LATCH-ENABLE-BIT_)
    newMask     |= (set << ALERT-LATCH-ENABLE-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    // if debug_: print "*      : alert-latch enable set from 0x$(%01x oldMask) to 0x$(%01x newMask)"
    if debug_: print "*      : alert-latch alert-pin $(set) is                          $(bits-16 oldMask) to $(bits-16 newMask)"

  // Human readable alias for setting alert latching
  //
  alert-latch --enable -> none:
    alert-latch --set=1

  // Human readable alias for setting alert latching
  //
  alert-latch --disable -> none:
    alert-latch --set=0

  // Retrieve Latch Configuration
  //
  alert-latch -> bool:
    mask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    latch/bool := false
    latchBit/int := ((mask & ALERT-LATCH-ENABLE-BIT_) >> ALERT-LATCH-ENABLE-OFFSET_) & ALERT-LATCH-ENABLE-LENGTH_
    if latchBit == 1: latch = true
    if debug_: print "*      : alert-latch is is $(latchBit) [$(latch)]"
    return latch
  
  // Alert pin polarity functions
  // NOTE:  
  //        1 = Inverted (active-high open collector)
  //        0 = Normal (active-low open collector) (default)
  //
  alert-pin-polarity --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(ALERT-PIN-POLARITY-BIT_)
    newMask     |= (set << ALERT-PIN-POLARITY-OFFSET_)
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    //if debug_: print "*      : alert-pin-polarity enable set from 0x$(%01x oldMask) to 0x$(%01x newMask)"
    if debug_: print "*      : alert-pin-polarity alert-pin $(set) is                   $(bits-16 oldMask) to $(bits-16 newMask)"

  // Human readable alias for setting alert pin polarity
  alert-pin-polarity --inverted -> none:  alert-pin-polarity --set=1
  alert-pin-polarity --normal   -> none:  alert-pin-polarity --set=0

  // Retrieve configured alert pin polarity setting
  //
  alert-pin-polarity -> bool:
    // inverted = true, normal = false
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    polarityInverted/bool := false
    polarityInvertedBit/int := ((oldMask & ALERT-PIN-POLARITY-BIT_) >> ALERT-PIN-POLARITY-OFFSET_) & ALERT-PIN-POLARITY-LENGTH_
    if polarityInvertedBit == 1: polarityInverted = true
    if debug_: print "*      : alert-pin-polarity is $(polarityInvertedBit) [$(polarityInverted)]"
    return polarityInverted

  // Alerts
  // NOTE:  Slightly different to the implementations I'd seen, I wanted alerts to
  //        be visible as a value on the class object, and not stored separately 
  //        from the source of truth.  So these functions attempt to source the current
  //        status of each alert from the device itself.
  
  // return true if any of the three alerts exists
  // NOTE:  done this way so that during debugging mode, the exact alert that triggered will be shown
  //        (more reads) whereas without debug mode, one read would suffice.
  alert -> bool:
    if debug_: 
      return overflow-alert or limit-alert or conversion-ready-alert
    else:
      register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
      checkMask    := ALERT-MATH-OVERFLOW-FLAG_ | ALERT-FUNCTION-FLAG_ | ALERT-CONVERSION-READY-FLAG_
      return (register & checkMask) != 0

  // clear alerts
  alert --clear -> none:
    // Not Tested - manual suggests reading the MASK-ENABLE is enough to clear any alerts
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_

  overflow-alert   -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    overflow := false
    overflowBit := ((register & ALERT-MATH-OVERFLOW-FLAG_) >> ALERT-MATH-OVERFLOW-OFFSET_ ) & ALERT-MATH-OVERFLOW-LENGTH_
    if overflowBit == 1: overflow = true
    if debug_: print "*      : alert: overflow bit is $(overflowBit) [$(overflow)]"
    return overflow

  limit-alert      -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    overflow := false
    overflowBit := ((register & ALERT-FUNCTION-FLAG_) >> ALERT-FUNCTION-OFFSET_ ) & ALERT-FUNCTION-LENGTH_
    if overflowBit == 1: overflow = true
    if debug_: print "*      : alert: configured limit bit is $(overflowBit) [$(overflow)]"
    return overflow

  // Determine If Conversion is Complete
  // Note:  Although the device can be read at any time, and the data from
  //        the last conversion is available, the Conversion Ready Flag bit is
  //        provided to help coordinate one-shot or triggered conversions. The 
  //        Conversion Ready Flag bit is set after all conversions, averaging, 
  //        and multiplications are complete. Conversion Ready Flag bit clears
  //        under the following conditions:
  //        1. Writing to the Configuration Register (except for Power-Down selection)
  //        2. Reading the Mask/Enable Register
  //
  conversion-ready-alert -> bool:
    register/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    conversionReady := false
    conversionReadyBit := ((register & ALERT-CONVERSION-READY-FLAG_) >> ALERT-CONVERSION-READY-OFFSET_ ) & ALERT-CONVERSION-READY-LENGTH_
    if conversionReadyBit == 1: conversionReady = true
    if debug_: print "*      : alert: conversion ready bit is $(conversionReadyBit) [$(conversionReady)]"
    return conversionReady

  // Alias for alert-conversion-ready
  //
  conversion-ready -> bool:
    return conversion-ready-alert
  
  // Configure the alert function enabling the pin to be used to signal conversion ready.
  //
  conversion-ready --set/int -> none:
    assert: 0 <= set <= 1
    oldMask/int := reg_.read-u16-be REGISTER-MASK-ENABLE_
    newMask/int := oldMask
    newMask     &= ~(CONVERSION-READY-BIT_)
    newMask     |= (set << CONVERSION-READY-OFFSET_) // already bit shifted
    reg_.write-u16-be REGISTER-MASK-ENABLE_ newMask
    if debug_: print "*      : conversion-ready alert-pin $(set) is                     $(bits-16 oldMask) to $(bits-16 newMask)"

  // Helpful alias for setting 'conversion-ready' on alert pin
  //
  conversion-ready --enable-alert-pin -> none:
    conversion-ready --set=1

  // Helpful alias for setting 'conversion-ready' on alert pin
  //
  conversion-ready --disable-alert-pin -> none:
    conversion-ready --set=0

  // Returns microsecs for TIMING-x-US statics 0..7
  // NOTE:  A helper function
  conversion-time-us-from-enum --code/int -> int:
    assert: 0 <= code <= 7
    if code == 0: return 140
    if code == 1: return 204
    if code == 2: return 332
    if code == 3: return 588
    if code == 4: return 1100
    if code == 5: return 2100
    if code == 6: return 4200
    if code == 7: return 8300
    return 1100  // default/defensive - should never happen

  // Returns sample count for AVERAGE-x-SAMPLE statics 0..7
  // NOTE:  A helper function
  sampling-rate-from-enum --code/int -> int:
    assert: 0 <= code <= 7
    if code == 0: return 1
    if code == 1: return 4
    if code == 2: return 16
    if code == 3: return 64
    if code == 4: return 128
    if code == 5: return 256
    if code == 6: return 512
    if code == 7: return 1024
    return 1  // default/defensive - should never happen

  // Estimate a maximum waiting time based on the configuration
  // NOTE:  Done this way to prevent setting a global maxWait type
  //        value, to then have it fail based on times that are longer
  //        due to timing configurations 
  estimated-conversion-time --ms -> int:
    // Read config and decode fields using masks/offsets
    register/int    := reg_.read-u16-be REGISTER-CONFIG_

    samplesCode/int    := (register & CONF-AVERAGE-MASK_)  >> CONF-AVERAGE-OFFSET_
    busCTcode/int      := (register & CONF-BUSVC-MASK_)    >> CONF-BUSVC-OFFSET_
    shuntCTcode/int    := (register & CONF-SHUNTVC-MASK_)  >> CONF-SHUNTVC-OFFSET_
    mode/int           := (register & CONF-MODE-MASK_)     >> CONF-MODE-OFFSET_

    samplingRate/int   := sampling-rate-from-enum            --code = samplesCode
    busCT/int          := conversion-time-us-from-enum       --code = busCTcode
    shuntCT/int        := conversion-time-us-from-enum       --code = shuntCTcode

    // Mode 0x7 = bus+shunt continuous, 0x3 = bus+shunt triggered (single-shot).
    // If converting to support bus-only or shunt-only modes, drop the other term.
    totalus/int    := (busCT + shuntCT) * samplingRate

    // Add a small guard factor (~10%) to be conservative
    totalus = ((totalus * 11.0) / 10.0).to-int

    // Return milliseconds, minimum 1 ms
    totalms := ((totalus + 999) / 1000).to-int  // ceil
    if totalms < 1: totalms = 1

    if debug_: print "*      : estimated-conversion-time --ms is: $(totalms)ms"
    return totalms

  // INFORMATION FUNCTIONS

  // Get Manufacturer/Die identifiers
  // NOTE:  maybe useful if expanding driver to suit an additional sibling device
  //
  manufacturer-id -> int:
    manid := reg_.read-u16-be REGISTER-MANUF-ID_
    if debug_: print "*      : manufacturer-id is 0x$(%04x manid) [$(manid)]"
    return manid
  
  // Device ID Bits
  // NOTE:  Bits 4-15 Stores the device identification bits
  // 
  device-identification -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    dieidDid := (register & DIE-ID-DID-MASK_) >> 4
    if debug_: print "*      : die-id DID is      0x$(%04x dieidDid) [$(dieidDid)]"
    return dieidDid

  // Die Revision ID Bits
  // NOTE:  Bit 0-3 Stores the device revision identification bits
  //
  device-revision -> int:
    register := reg_.read-u16-be REGISTER-DIE-ID_
    dieidRid := (register & DIE-ID-RID-MASK_)
    if debug_: print "*      : die-id RID is      0x$(%04x dieidRid) [$(dieidRid)]"
    return dieidRid

  // TROUBLESHOOTING FUNCTIONS

  // Infer Shunt Resistor using a known load resistor
  // NOTE:  Averages a few samples for stability, ensures both voltages come from the
  //        same conversion, and returns the estimated shunt value.
  // NOTE:  On Accuracy:
  //        - Known load tolerance dominates: use a 0.1–1% resistor if possible
  //        - Make sure VBUS & load node (IN−) are tied
  //        - Kelvin the shunt if possible: sense pins at the shunt pads
  //        - Perform test/readings after the load settles - average some samples
  //        - Low-current corner: if Vshunt is just a few tens of µV, quantization/noise
  //          can move the estimate; use a load that draws a few mA+ to get a clean mV-level Vsh.
  infer-shunt-resistor --loadResistor/float -> float:
    assert: loadResistor > 0.0

    // Make sure we read one coherent conversion
    single-measurement
    wait-until-conversion-completed

    // Light Averaging
    loadVoltageSum/float       := 0.0
    shuntVoltageSum/float      := 0.0
    samples                    := 8
    samples.repeat:
      loadVoltageSum           += bus-voltage --volts
      shuntVoltageSum          += shunt-voltage --volts

    // Replace values with calculated average
    loadVoltage/float          := loadVoltageSum / samples.to-float
    shuntVoltage/float         := shuntVoltageSum   / samples.to-float

    // Estimate current via Ohm's law on the known load
    currentEstimate/float := loadVoltage / loadResistor
    assert: currentEstimate > 0.0

    shuntResistorEstimate/float := shuntVoltage / currentEstimate
    print "Infer shunt: Vload=$(loadVoltage) V  Vsh=$(shuntVoltage) V  Rload=$(loadResistor) Ohm  -> I=$(currentEstimate)A  Rsh_est=$(shuntResistorEstimate) Ohm"
    return shuntResistorEstimate

  // Determine shunt resistor value from known load
  // NOTE:  See notes above for similar function.
  //        Useful if you have a DMM clamp or source  
  infer-shunt-resistor --loadCurrent/float -> float:
    assert: loadCurrent > 0.0

    // Make sure we read one coherent conversion
    single-measurement
    wait-until-conversion-completed
    
    // take some samples and average the shuntVoltage a bit
    shuntVoltageSum/float       := 0.0
    samples                     := 8
    samples.repeat:
      shuntVoltageSum += shunt-voltage --volts
      
    shuntVoltage/float          := shuntVoltageSum / samples.to-float
    shuntResistorEstimate/float := shuntVoltage / loadCurrent
    print "Infer shunt: Vsh=$(shuntVoltage)V  I_known=$(loadCurrent)A  -> Rsh_est=$(shuntResistorEstimate)Ω"
    return shuntResistorEstimate


  // Determine VBUS and VLOAD are different
  // NOTE:  Evaluates if the bus and load voltages are different (eg not tied).
  //        Useful for diagnostic functions only.  If the voltages are the same,
  //        it is not proof that they are tied, this attempts to check for the
  //        simple case where values indiate it is not tied.
  //
  verify-tied-bus-load -> bool:
    // Optional: ensure fresh data
    single-measurement
    wait-until-conversion-completed

    busVoltage/float := bus-voltage --volts
    loadVoltage/float := load-voltage --volts
    busLoadDelta/float := (busVoltage - loadVoltage).abs
  
    if debug_: print "Bus = $(%0.8f busVoltage)V, Load = $(%0.8f loadVoltage)V, Delta = $(%0.8f busLoadDelta)V"
    if busLoadDelta < 0.01:       // <10 mV difference
      if debug_: print " Bus and load values appear the same (tied?)     Delta=$(%0.8f busLoadDelta)V"
      return true
    else if busLoadDelta < 0.05:  // 10–50 mV: maybe wiring drop
      if debug_: print " Bus/load differ slightly (check traces/wiring)  Delta=$(%0.8f busLoadDelta)V"
      return false
    else:
      if debug_: print " Bus and load differ significantly (not tied)    Delta=$(%0.8f busLoadDelta)V"
      return false

  // Print Diagnostic Information
  // NOTE:  Prints relevant measurement information to allow someone with a
  //        Voltmeter to double check what is measured and compare it.  Also
  //        calculates/compares using Ohms Law (V=I*R)
  //
  print-diagnostics -> none:
    // Optional: ensure fresh data
    single-measurement
    wait-until-conversion-completed

    shuntVoltage/float               := shunt-voltage --volts
    loadVoltage/float                := bus-voltage --volts              // what the load actually sees (VBUS, eg IN−)
    supplyVoltage/float              := loadVoltage + shuntVoltage       // upstream rail (IN+ = IN− + Vsh)
    shuntVoltageDelta/float          := supplyVoltage - loadVoltage      // same as vsh
    shuntVoltageDeltaPct/float       := 0.0
    if supplyVoltage > 0.0: shuntVoltageDeltaPct = (shuntVoltageDelta / supplyVoltage) * 100.0

    calibrationValue/int             := calibration-value
    currentRaw/int                   := reg_.read-i16-be REGISTER-SHUNT-CURRENT_
    leastSignificantBit/float        := 0.00512 / (calibrationValue.to-float * shunt-resistor_)
    currentChip/float                := currentRaw * leastSignificantBit
    currentVR/float                  := shuntVoltage / shunt-resistor_

    // CROSSCHECK: between chip/measured current and V/R reconstructed current
    currentDifference/float          := (currentChip - currentVR).abs
    currentDifferencePct/float       := 0.0
    if (currentVR != 0.0): 
      currentDifferencePct           = (currentDifference / currentVR) * 100.0

    // CROSSCHECK: shunt voltage (measured vs reconstructed)
    shuntVoltageCalculated/float     := currentChip * shunt-resistor_
    shuntVoltageDifference/float     := (shuntVoltage - shuntVoltageCalculated).abs
    shuntVoltageDifferencePct/float  := 0.0
    if (shuntVoltage != 0.0): 
      shuntVoltageDifferencePct      = (shuntVoltageDifference / shuntVoltage).abs * 100.0

    print "DIAG :"
    print "    ----------------------------------------------------------"
    print "    Shunt Resistor    =  $(%0.8f shunt-resistor_) Ohm (Configured in code)"
    print "    Vload    (IN-)    =  $(%0.8f loadVoltage)  V"
    print "    Vsupply  (IN+)    =  $(%0.8f supplyVoltage)  V"
    print "    Shunt V delta     =  $(%0.8f shuntVoltageDelta)  V"
    print "                      = ($(%0.8f shuntVoltageDelta*1000.0)  mV)"
    print "                      = ($(%0.3f shuntVoltageDeltaPct)% of supply)"
    print "    Vshunt (direct)   =  $(%0.8f shuntVoltage)  V"
    print "    ----------------------------------------------------------"
    print "    Calibration Value =  $(calibrationValue)"
    print "    I (raw register)  = ($(currentRaw))"
    print "                 LSB  = ($(%0.8f leastSignificantBit)  A/LSB)"
    print "    I (from module)   =  $(%0.8f currentChip)  A"
    print "    I (from V/R)      =  $(%0.8f currentVR)  A"
    print "    ----------------------------------------------------------"
    if currentDifferencePct < 5.0:
      print "    Check Current       : OK - Currents agree ($(%0.3f currentDifferencePct)% under/within 5%)"
    else if currentDifferencePct < 20.0:
      print "    Check Current       : WARNING (5% < $(%0.3f currentDifferencePct)% < 20%) - differ noticeably"
    else:
      print "    Check Current       : BAD!! ($(%0.3f currentDifferencePct)% > 20%): check calibration or shunt value"
    if shuntVoltageDifferencePct < 5.0:
      print "    Check Shunt Voltage : OK - Shunt voltages agree ($(%0.3f shuntVoltageDifferencePct)% under/within 5%)"
    else if shuntVoltageDifferencePct < 20.0:
      print "    Check Shunt Voltage : WARNING (5% < $(%0.3f shuntVoltageDifferencePct)% < 20%) - differ noticeably"
    else:
      print "    Check Shunt Voltage : BAD!! ($(%0.3f shuntVoltageDifferencePct)% > 20%): shunt voltage mismatch"

  // Helper Function for displaying bitmasks nicely
  //
  bits-16 x/int -> string:
    outStr := "$(%b x)"
    outStr = outStr.pad --left 16 '0'
    outStr = "$(outStr[0..4]).$(outStr[4..8]).$(outStr[8..12]).$(outStr[12..16])"
    return outStr

/*

void WE::setCurrentRange(CURRENT-RANGE range){ // deprecated, left for downward compatibility
    deviceCurrentRange = range    
}

*/
