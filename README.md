# simple_directory_backup.ps1

A comprehensive PowerShell script designed to back up one or more directories on a Windows host, compress them, and upload them to an S3-compatible provider of your choice. It also includes support for Telegram notifications.

This script is intended for backing up smaller directories containing many small files that need to be kept as a set, such as AI training data, flat-file databases, configuration files, etc. It is not recommended for backing up large directories, as the script compresses the entire directory into a single file, which can take a considerable amount of time depending on the directory's size.

This script leverages the following open-source projects:
- albertony's [ShadowRun](https://github.com/albertony/vss/tree/master/shadowrun)
- Tino Reichardt's [7Zip ZS](https://github.com/mcmilk/7-Zip-zstd)
- The cloud storage Swiss Army Knife [rclone](https://rclone.org)

## Features:
- Automatic dependency management
- Automatic rclone configuration
- Capability to back up multiple directories
- Creates a Volume Shadow Copy of the directory before compression
- Utilizes [ZStandard](https://github.com/facebook/zstd) at Level 1 for an optimal balance of compression speed and storage efficiency
- Uploads to any S3-compatible storage provider
- Safe for use with Windows Task Scheduler™ thanks to robust error-checking
- Comprehensive logging to file and alerting via Telegram
- dotenv configuration management

## Instructions:
- Copy `sample.env` to `.env` and edit the values to match your environment.
- You may add more `DIR_n` variables as required.
- If you already have the rclone or ShadowRun binary installed, you can optionally point the script to it, and it will use that instead of downloading it from the web.
- Add the script as an action in your scheduled backup task.

This script requires PowerShell version 5.1 or later.  
This script requires the Visual C++ Redistributable to be installed. It will be installed automatically if not present.
