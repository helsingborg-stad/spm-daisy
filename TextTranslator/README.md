# TextTranslator

TextTranslator provides a common interface for Text translation services implementing the `TextTranslationService` protocol.

## Text Translation Services
The TextTranslator does not work on it's own but needs an implementation of `TextTranslationService`. Right now there is only one known implementation:

|Name|Package|
|:--|:--|
|MSTTS| included in https://github.com/helsingborg-stad/spm-ms-cognitive-services|

## Usage
You can either use `TextTranslator` singleton or use a concrete implementation of `TextTranslatorService` as is. 

```swift
let translator = TextTranslator(service: MyTextTranslatorService())
let strings = ["My untranslated text"]
let dictionary = ["my_key":"My untranslated text"]

translator.translate(strings, from: "se", to: ["en"]).sink { compl in
    if case let .failure(error) = compl {
        debugPrint(error)
    }
} receiveValue: { table in
    print(table.value(forKey:"My untranslated text", in:"en"))
}.store(in: &cancellables)


translator.translate(dictionary, from: "se", to: ["en"]).sink { compl in
    if case let .failure(error) = compl {
        debugPrint(error)
    }
} receiveValue: { table in
    print(table.value(forKey:"my_key", in:"en"))
}.store(in: &cancellables)
```

If you wish to take your translations to the next level you should have a look at 
[Dragoman](https://github.com/helsingborg-stad/spm-dragoman).


## Testing
The tests does not cover a concrete implementation of a `TextTranslationService`, only the `TextTranslationTable` and the `TextTranslator` singleton. 

## TODO
- [x] add list of available services
- [x] code-documentation
- [x] write tests
- [x] complete package documentation
