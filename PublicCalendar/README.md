# PublicCalendar

Service that fetches swedish public holidays etc from www.kalender.se.

## Usage

The `publisher(for: on:)` method can be great for observing changes to the calendar.   
```swift 
var cancellables = Set<AnyCancellable>()

let publicCalendar = PublicCalendar(fetchAutomatically: true)
/// subscribe to the latest events by the following filters. If the database is empty or waiting to be fetched, the result will be nil.
publicCalendar.publisher(for: [.holidays], on: Date()).sink { events in 
    guard let events = events else {
        return 
    }
}.store(in: &cancellables)
``` 

## TODO

- [x] code-documentation
- [x] write tests
- [x] complete package documentation
