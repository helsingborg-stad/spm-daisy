# Instagram

Instagram API implementation.

## Usage


### Setup instagram instance
To learn how to set up an instagram app in the facebook developers portal, please consult https://developers.facebook.com/docs/instagram-basic-display-api/overview.

Once that's completed you can go ahead and set up your instance. Preferably you would keep the instance for the duration of the apps lifetime. 
```swift
gaurd let serverURL = URL(string:"https://myserver.com/instagram") else {
    fatalError("faulty url")
}

/// If you can, exclude the clientId from the app binary. Preferably it should be pushed using MDM AppConfg.
let clientId = "app client id"
let config = Instagram.Config(
    serverURL: serverURL, 
    callbackScheme: "myappurlscheme", 
    clientId: clientId, 
    keychainServiceName: "myapp", 
    keychainCredentialsKey: "instagramcredentials"
)
let instagram = Instagram(config:config)
```

### Authorization
Before you can fetch media you must call authorize in some way. Perhaps via a button: 

```swift
Button(action: {
    if instagram.isAuthenticated {
        instagram.logout()
    } else {
        instagram.authorize().sink { completion in
            switch completion{
            case .failure(let error): debugPrint("handle instagram error somehow", error)
            case .finished: break;
            }
        } receiveValue: {
            debugPrint("completed authorization")
        }.store(in: &cancellables)
    }
}) {
    if instagram.isAuthenticated {
        Text("Logout from Instagram").foregroundColor(.red)
    } else {
        Text("Connect Instagram account")
    }
}
```

### Fetch media
Fetching media is as easy as subscribing to the `latest` publisher.

```swift
/// When you attach your subscriber a fetch will be initiated automatically if the fetchAutomatiaclly is set to true.
instagram.latest.sink { media in
    /// The latest publisher will aways yield a result, so before a succesful fetch has been completed, the first result will be nil.
    guard let media = media else {
        return
    }
}
```

## TODO

- [x] add keychain options?
- [ ] add pagniation implementation
- [x] code-documentation
- [ ] write tests
- [ ] complete package documentation
