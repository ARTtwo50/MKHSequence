//
//  Main.swift
//  MKHSequence
//
//  Created by Maxim Khatskevich on 11/26/15.
//  Copyright © 2015 Maxim Khatskevich. All rights reserved.
//

import UIKit

//===

private
func runOnMain(block: () -> Void)
{
    NSOperationQueue.mainQueue()
        .addOperationWithBlock(block)
}

public
final
class Sequence
{
    // MARK: Properties - Private
    
    private
    var inputData: Any? = nil
    
    private
    var tasks: [Task] = []
    
    private
    var onComplete: CompletionHandler?
    
    private
    var onFailure: FailureHandler?
    
    private
    var isCancelled: Bool // calculated helper property
    {
        return status == .Cancelled
    }
    
    private
    var targetTaskIndex = 0
    
    // MARK: Nested types and aliases
    
    public
    typealias Task = (sequence: Sequence, previousResult: Any?) throws -> Any?
    
    public
    typealias FailureHandler = (sequence: Sequence, error: ErrorType) -> Void
    
    public
    typealias CompletionHandler = (sequence: Sequence, lastResult: Any?) -> Void
    
    // MARK: Properties - Public
    
    public private(set)
    var name: String?
    
    public
    static
    var defaultTargetQueue = NSOperationQueue()
    
    public
    var targetQueue: NSOperationQueue!
    
    public
    enum Status: String
    {
        case
            Pending,
            Processing,
            Failed,
            Completed,
            Cancelled
    }
    
    public private(set)
    var status: Status = .Pending
    
    public private(set)
    var failedAttempts: UInt = 0
    
    // MARK: Init
    
    public
    init(name: String? = nil, targetQueue: NSOperationQueue = Sequence.defaultTargetQueue)
    {
        self.name = name
        self.targetQueue = targetQueue
    }
    
    // MARK: Methods - Private
    
    private
    func shouldProceed() -> Bool
    {
        return (targetTaskIndex < self.tasks.count)
    }
    
    private
    func executeNext(previousResult: Any? = nil)
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if
            shouldProceed()
        {
            // regular block
            
            let task = tasks[targetTaskIndex]
            
            //===
            
            targetQueue
                .addOperationWithBlock({ () -> Void in
                    
                    do
                    {
                        let result = try task(sequence: self, previousResult: previousResult)
                        
                        //===
                        
                        // everything seems to be good,
                        // lets continue execution
                        
                        self.proceed(result)
                    }
                    catch let error
                    {
                        // the task trown an error
                        
                        self.reportFailure(error)
                    }
                })
        }
        else
        {
            executeCompletion(previousResult)
        }
    }
    
    private
    func reportFailure(error: ErrorType)
    {
        runOnMain {
            
            if self.status == .Processing
            {
                self.status = .Failed
                
                //===
                
                self.failedAttempts += 1
                
                //===
                
                if let failureHandler = self.onFailure
                {
                    failureHandler(sequence: self, error: error)
                }
            }
        }
    }
    
    private
    func proceed(previousResult: Any? = nil)
    {
        runOnMain { 
            
            if self.status == .Processing
            {
                self.targetTaskIndex += 1
                
                //===
                
                self.executeNext(previousResult)
            }
        }
    }
    
    private
    func executeCompletion(lastResult: Any? = nil)
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        status = .Completed
        
        //===
        
        if
            let completionHandler = self.onComplete
        {
            completionHandler(sequence: self, lastResult: lastResult);
        }
    }
    
    private
    func reset() -> Bool
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        var result = false
        
        //===
        
        switch status
        {
            case .Failed, .Completed, .Cancelled:
                
                targetTaskIndex = 0
                status = .Pending
                
                //===
                
                result = true
                
            default:
                break // ignore
        }
        
        //===
        
        return result
    }
    
    // MARK: Methods - Public
    
    public
    func input(data: Any) -> Self
    {
        if status == .Pending
        {
            self.inputData = data
        }
        
        //===
        
        return self
    }
    
    public
    func beginWith<InputDataType>(preparation: () -> InputDataType?) -> Self
    {
        if status == .Pending
        {
            self.inputData = preparation()
        }
        
        //===
        
        return self
    }
    
    public
    func add<PreviousResultType: Any, ResultType: Any>(
        customTask: (sequence: Sequence, previousResult: PreviousResultType?) throws -> ResultType?
        ) -> Self
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if status == .Pending
        {
            let genericTask: Task = { (sequence, previousResult) throws -> Any? in
                
                return
                    try customTask(
                        sequence: sequence,
                        previousResult: previousResult as? PreviousResultType)
            }
            
            //===
            
            tasks.append(genericTask)
        }
        
        //===
        
        return self
    }
    
    public
    func then<PreviousResultType, ResultType>(
        task: (sequence: Sequence, previousResult: PreviousResultType?) throws -> ResultType?
        ) -> Self
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        return add(task)
    }
    
    public
    func onFailure(failureHandler: FailureHandler) -> Self
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if status == .Pending
        {
            onFailure = failureHandler
        }
        
        //===
        
        return self
    }
    
    public
    func finally<LastResultType: Any>(
        completion: (sequence: Sequence, lastResult: LastResultType?) -> Void
        ) -> Self
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if status == .Pending
        {
            let genericCompletion: CompletionHandler = { sequence, lastResult in
                
                return completion(sequence: sequence, lastResult: lastResult as? LastResultType)
            }
            
            //===
            
            onComplete = genericCompletion
            
            //===
            
            start()
        }
        
        //===
        
        return self
    }
    
    public
    func start() -> Self
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if status == .Pending
        {
            status = .Processing
            
            //===
            
            executeNext(self.inputData)
        }
        
        //===
        
        return self
    }
    
    public
    func cancel()
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        switch status
        {
            case .Pending, .Processing:
                status = .Cancelled
            
            default:
                break // ignore
        }
    }
    
    public
    func executeAgain() // (after: NSTimeInterval = 0)
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        if reset()
        {
            start()
        }
    }
    
    public
    func executeAgain(after interval: NSTimeInterval)
    {
        // NOTE: this mehtod is supposed to be called on main queue
        
        //===
        
        let delay = dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(interval * Double(NSEC_PER_SEC)))
        
        dispatch_after(delay, dispatch_get_main_queue()) { 
            
            self.executeAgain()
        }
    }
}
