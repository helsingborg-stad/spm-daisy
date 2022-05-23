import Combine
import Foundation

/// Used by implementing classes in order to make a class compatible with the `TaskQueue`
public protocol QueueTask : AnyObject {
    /// The id of the task
    var id: UUID { get }
    /// A publsiher triggering when the task has finished (or is cancelled)
    var end: AnyPublisher<Void, Never> { get }
    /// For when the task will run
    func run()
    /// Used to interrupt the task
    func interrupt()
    /// Used to pause the task
    func pause()
    /// Used to continue the task
    func `continue`()
}
/// Manages a queue of async tasks to run.
public class TaskQueue : ObservableObject {
    /// Cancellable store
    private var cancellables = Set<AnyCancellable>()
    /// A queue of tasks
    private var queue = [QueueTask]()
    /// The currently running task
    private var currentTask:QueueTask?
    
    /// Subscribes to tasks
    /// - Parameter task: the tasks to subscribe to
    private func subscribe(to task:[QueueTask]) {
        task.forEach { t in
            subscribe(to: t)
        }
    }
    /// Subscribes to a task.end publisher
    /// - Parameter task: The task to subscribe to
    private func subscribe(to task:QueueTask) {
        var p:AnyCancellable?
        p = task.end.receive(on: DispatchQueue.main).sink { [weak self] in
            guard let this = self else {
                return
            }
            if task.id == this.currentTask?.id {
                this.currentTask = nil
            }
            if let p = p {
                self?.cancellables.remove(p)
            }
            this.runQueue()
        }
        if let p = p {
            cancellables.insert(p)
        }
    }
    /// Interrupcs and removes all currently queue (and running) tasks
    public func clear() {
        for t in queue {
            t.interrupt()
        }
        currentTask?.interrupt()
        currentTask = nil
        cancellables.removeAll()
        queue.removeAll()
    }
    /// Run he queue by calling Task.run on the first task in the Self.queue
    private func runQueue() {
        if currentTask != nil {
            return
        }
        guard let task = queue.first else {
            return
        }
        queue.removeFirst()
        self.currentTask = task
        task.run()
    }
    /// Initialize a new instance
    public init() {}
    
    /// Queue a new task, adding it to the end of the queue
    /// - Parameter task: the task to queue
    public final func queue(_ task:QueueTask) {
        queue.append(task)
        subscribe(to: task)
        runQueue()
    }
    /// Queue a set of tasks, adding them it to the end of the queue in the order of the provided array
    /// - Parameter task: the tasks to queue
    public final func queue(_ tasks:[QueueTask]) {
        tasks.forEach { t in
            queue(t)
        }
    }
    /// Interject by pausing the current task and adding a task at the top of the queue and running it.
    /// Once the new task has been completed the paused task will be continued
    /// - Parameter task: the task to use for interjection
    public final func interject(with task:QueueTask) {
        if let c = currentTask {
            subscribe(to: task)
            c.pause()
            queue.insert(contentsOf: [task,c],at:0)
            self.currentTask = nil
            runQueue()
        } else {
            queue(task)
        }
    }
    /// Interject by pausing the current task and adding a set of tasks at the top of the queue and running them.
    /// Once the tasks has been completed the paused task will be continued
    /// - Parameter task: the task to use for interjection
    public final func interject(with tasks:[QueueTask]) {
        if let c = currentTask {
            subscribe(to: tasks)
            var tasks = tasks
            tasks.append(c)
            c.pause()
            queue.insert(contentsOf: tasks,at:0)
            self.currentTask = nil
            runQueue()
        } else {
            queue(tasks)
        }
    }
    /// Interrupt (clears) all current tasks (queued and running) and add a new task at the top of the queue and running it
    /// - Parameter task: the task used for interruption
    public final func interrupt(with task:QueueTask) {
        clear()
        queue(task)
    }
    /// Interrupt (clears) all current tasks (queued and running) and adds a set of tasks at the top of the queue and running them in order.
    /// - Parameter task: the tasks used for interruption
    public final func interrupt(with tasks:[QueueTask]) {
        clear()
        queue(tasks)
    }
}
