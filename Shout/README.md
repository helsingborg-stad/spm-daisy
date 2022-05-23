# Shout
Code logger with file, function and code-line support. 

## Usage
Shout writes "Apple styled messages" to your xcode debug output via the `OSLog` library.

```swift
class MyCode {
    var logger = Shout("MyCode")
    var analytics = MyAnalyticsService()
    init() {
        // You might already a service that manages app logging events. 
        // Using the event-publisher you can make sure your service gets 
        // all messages. This comes in handy of a third party library 
        // is using Shout.
        logger.publisher.sink { event in 
            guard event.level == .error else { return }
            analytics.logErrorEvent(event.description)
        }.store(in: &globalCancellables)
    }
    func doSomething() {
        logger.info("Starting to do something")
        do {
            try throwableFeature()
        } catch {
            logger.error("the throwable feature failed with an error", error)
        }
        logger.info("Stopped doing something")
    }
    func doSomethingElse() {
        logger.warning("This methods function has not been implemeted")
    }
}
``` 

## TODO
- [x] code-documentation
- [x] write tests
- [x] complete package documentation
