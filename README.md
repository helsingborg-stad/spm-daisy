# Daisy

<!-- HEADS UP! To avoid retyping too much info. Do a search and replace with your text editor for the following:
repo_name, project_name -->

<!-- SHIELDS -->
![platform][platform-shield]
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![License][license-shield]][license-url]

<p>
  <a href="https://github.com/helsingborg-stad/spm-daisy-collection">
    <img src="hbg-github-logo-combo.png" alt="Logo" width="300">
  </a>
</p>

# SPM Daisy Collection
SPM Daisy is a collection of Swift libraries that Helsingborg has used to create digital assistants.

## Table of Contents
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [License](#license)


## Getting Started

### Prerequisites
* [Xcode](https://developer.apple.com/xcode/)

### Installation
Add the package collection to Xcode:
- Open a project
- From the Xcode menu select **File** -> **Add Packages**
- Search for `spm-daisy` at the top of the screen and hit enter
- Select any library that you are interested in, and rememeber, you can always add more later.

## Usage
Each library develiers a specific functionality and each of them has documentation on how to use it. To get started we recommend you have a look at the [Assistant](Documentation/Assistant) library.

| Package | Description |
|:--|:--|                                                   
| [AppSettings](AppSettings)                                             | Digital assitant interface
| [Assistant](Assistant)                                                 | Audio service management
| [AudioSwitchboard](AudioSwitchboard)                                   | Configuration with MDM App Config support
| [AutomatedFetcher](AutomatedFetcher)                                   | Reccuring fetches
| [Dragoman](Dragoman)                                                   | String localization management
| [FFTPublisher](FFTPublisher)                                           | Audio visualization
| [Instagram](Instagram)                                                 | Instagram API inter
| [Meals](Meals)                                                         | For fetching meals
| [PublicCalendar](PublicCalendar)                                       | Swedish public calendar
| [Shout](Shout)                                                         | Debug logging
| [STT](STT)                                                             | Speech to text
| [TTS](TTS)                                                             | Text to speech
| [TextTranslator](TextTranslator)                                       | Text translation
| [Weather](Weather)                                                     | Weather service interface

## More packages
There are other packages available to use in your apps, like the [MSCognitiveServices](https://github.com/helsingborg-stad/spm-ms-cognitive-services) that implements the TextTransaltor, STT and TTS protocols for easy use within your app.

| Package | Description |
|:--|:--|       
| [MSCognitiveServices](https://github.com/helsingborg-stad/spm-ms-cognitive-services)    | Adapted Microsoft Services

## Contributing
Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License
Distributed under the [MIT License][license-url].



<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/helsingborg-stad/spm-daisy-collection.svg?style=flat-square
[contributors-url]: https://github.com/helsingborg-stad/spm-daisy-collection/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/helsingborg-stad/spm-daisy-collection.svg?style=flat-square
[forks-url]: https://github.com/helsingborg-stad/spm-daisy-collection/network/members
[stars-shield]: https://img.shields.io/github/stars/helsingborg-stad/spm-daisy-collection.svg?style=flat-square
[stars-url]: https://github.com/helsingborg-stad/spm-daisy-collection/stargazers
[issues-shield]: https://img.shields.io/github/issues/helsingborg-stad/spm-daisy-collection.svg?style=flat-square
[issues-url]: https://github.com/helsingborg-stad/spm-daisy-collection/issues
[license-shield]: https://img.shields.io/github/license/helsingborg-stad/spm-daisy-collection.svg?style=flat-square
[license-url]: https://raw.githubusercontent.com/helsingborg-stad/spm-daisy-collection/main/LICENSE
[platform-shield]: https://img.shields.io/badge/platform-iOS-blue.svg?style=flat-square

## Libraries
- [AppSettings](Documentation/AppSettings.md)
- [Assistant](Documentation/Assistant.md)
- [AudioSwitchboard](Documentation/AudioSwitchboard.md)
- [AutomatedFetcher](Documentation/AutomatedFetcher.md)
- [ClockUI](Documentation/ClockUI.md)
- [Dragoman](Documentation/Dragoman.md)
- [FFTPublisher](Documentation/FFTPublisher.md)
- [Instagram](Documentation/Instagram.md)
- [Meals](Documentation/Meals.md)
- [PublicCalendar](Documentation/PublicCalendar.md)
- [ClockUI](Documentation/ClockUI.md)
- [Shout](Documentation/Shout.md)
- [TTS](Documentation/TTS.md)
- [TextTranslator](Documentation/TextTranslator.md)
- [Weather](Documentation/Weather.md)
