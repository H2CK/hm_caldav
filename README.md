## CalDav integration for HomeMatic - hm_caldav

[![Release](https://img.shields.io/github/release/H2CK/hm_caldav.svg)](https://github.com/H2CK/hm_caldav/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/H2CK/hm_caldav/latest/total.svg)](https://github.com/H2CK/hm_caldav/releases/latest)
[![Issues](https://img.shields.io/github/issues/H2CK/hm_caldav.svg)](https://github.com/H2CK/hm_caldav/issues)
[![License](http://img.shields.io/:license-lgpl3-blue.svg?style=flat)](http://www.gnu.org/licenses/lgpl-3.0.html)
[![Donate](https://img.shields.io/badge/donate-PayPal-green.svg)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=QRSDVQA2UMJQC&source=url)


This CCU-Addon reads an ics file from the given url. In the configuration you can define which meeting are represented as system variables within the HomeMatic CCU environment. If a defined meeting is running this is represented by the value of the corresponding system variable.
Additionally there are variables -TODAY and -TOMORROW which are set to active if a meeting is planned today or tommorow, even if the meeting only last for e.g. an hour.

Important: This addon is based on wget. On your CCU there might be an outdated version of wget, which might not support TLS 1.1 or TLS 1.2.

## Supported CCU models
* [HomeMatic CCU3](https://www.eq-3.de/produkte/homematic/zentralen-und-gateways/smart-home-zentrale-ccu3.html) / [RaspberryMatic](http://raspberrymatic.de/)
* [HomeMatic CCU2](https://www.eq-3.de/produkt-detail-zentralen-und-gateways/items/homematic-zentrale-ccu-2.html)
* HomeMatic CCU1

## Installation as CCU Addon
1. Download of recent Addon-Release from [Github](https://github.com/H2CK/hm_caldav/releases)
2. Installation of Addon archive (```hm_caldav-X.X.tar.gz```) via WebUI interface of CCU device
3. Configuration of Addon using the WebUI accessible config pages

## Manual Installation as stand-alone script (e.g. on RaspberryPi)
1. Create a new directory for hm_caldav:

        mkdir /opt/hm_caldav

2. Change to new directory: 

        cd /opt/hm_caldav

3. Download latest hm_caldav.sh:

        wget https://github.com/H2CK/hm_caldav/raw/master/hm_caldav.sh

4. Download of sample config:

        wget https://github.com/H2CK/hm_caldav/raw/master/hm_caldav.conf.sample

5. Rename sample config to active one:

        mv hm_caldav.conf.sample hm_caldav.conf

6. Modify configuration according to comments in config file:

        vim hm_caldav.conf

7. Execute hm_caldav manually:

        /opt/hm_caldav/hm_caldav.sh

8. If you want to automatically start hm_caldav on system startup a startup script

## Using 'system.Exec()'
Instead of automatically calling hm_caldav on a predefined interval one can also trigger its execution using the `system.Exec()` command within HomeMatic scripts on the CCU following the following syntax:

        system.Exec("/usr/local/addons/hm_caldav/run.sh <iterations> <waittime> &");
 
Please note the &lt;iterations&gt; and &lt;waittime&gt; which allows to additionally specify how many times hm_caldav should be executed with a certain amount of wait time in between. One example of such an execution can be:

        system.Exec("/usr/local/addons/hm_caldav/run.sh 5 2 &");

This will execute hm_caldav for a total amount of 5 times with a waittime of 2 seconds between each execution.

## Support
In case of problems/bugs or if you have any feature requests please feel free to open a [new ticket](https://github.com/H2CK/hm_caldav/issues) at the Github project pages.

## License
The use and development of this addon is based on version 3 of the LGPL open source license.

## Authors
Copyright (c) 2018-2021 Thorsten Jagel &lt;dev@jagel.net&gt;

## Notice
This Addon uses KnowHow that was developed throughout the following projects:
* https://github.com/jens-maus/hm_pdetect
