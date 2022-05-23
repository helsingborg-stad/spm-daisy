# AutomatedFetcher

A support libarary to manage automatic network fetches. The library was created in order to standardize automatic fetches across network libraries. 

## Usage

The implemeting library must trigger `started()`, `completed()` and `failed()` functions whenever appropriate.  
```swift 
class MyNetworkFether {
    let value = CurrentValueSubject<String,Never>("")
    let fetcher:AutomatedFetcher<String>
    var cancellables = Set<AnyCancellable>()
    init() {
        fetcher = AutomatedFetcher<String>(value, isOn: true, timeInterval: 20)
        fetcher.triggered.sink { [weak self] in
            self?.fetch()
        }.store(in: &cancellables)
    }
    func fetch() {
        fetcher.started()
        URLSession.shared.dataTaskPublisher(for: URL(string: "https://www.tietoevry.com")!)
            .map { $0.data }
            .tryMap { data -> String in
                guard let value = String(data: data,encoding:.utf8) else {
                    throw URLError(.unknown)
                }
                return value
            }.sink { [weak self] compl in
                switch compl {
                case .failure(let error):
                    debugPrint(error)
                    self?.fetcher.failed()
                case .finished: break;
                }
            } receiveValue: { [weak self] value in
                self?.value.send(value)
                self?.fetcher.completed()
            }.store(in: &cancellables)
    }
}
```
