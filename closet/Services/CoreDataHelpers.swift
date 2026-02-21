//
//  CoreDataHelpers.swift
//  closet
//
//  Created by Dan Warner on 1/27/25.
//

import Foundation
import CoreData

/// Helper function to set updatedAt timestamp on entities before saving
func setUpdatedAt<T: NSManagedObject>(_ entity: T) {
    // Check if entity has updatedAt property and set it
    if entity.entity.attributesByName["updatedAt"] != nil {
        entity.setValue(Date(), forKey: "updatedAt")
    }
}

/// Helper function to set updatedAt on multiple entities
func setUpdatedAt<T: NSManagedObject>(_ entities: [T]) {
    for entity in entities {
        setUpdatedAt(entity)
    }
}

/// Helper function to set createdAt and updatedAt when creating new entities
func setCreatedAndUpdatedAt<T: NSManagedObject>(_ entity: T) {
    let now = Date()
    if entity.entity.attributesByName["createdAt"] != nil {
        entity.setValue(now, forKey: "createdAt")
    }
    if entity.entity.attributesByName["updatedAt"] != nil {
        entity.setValue(now, forKey: "updatedAt")
    }
}

/// Helper function to soft delete an entity (sets isSoftDeleted = true)
func softDelete<T: NSManagedObject>(_ entity: T) {
    // Check if entity has isSoftDeleted property
    if entity.entity.attributesByName["isSoftDeleted"] != nil {
        entity.setValue(true, forKey: "isSoftDeleted")
        setUpdatedAt(entity)
    } else {
        // Fallback to hard delete if entity doesn't support soft delete
        entity.managedObjectContext?.delete(entity)
    }
}

/// Helper function to restore a soft-deleted entity
func restoreSoftDeleted<T: NSManagedObject>(_ entity: T) {
    if entity.entity.attributesByName["isSoftDeleted"] != nil {
        entity.setValue(false, forKey: "isSoftDeleted")
        setUpdatedAt(entity)
    }
}

/// Helper function to check if entity is soft deleted
func isSoftDeleted<T: NSManagedObject>(_ entity: T) -> Bool {
    guard entity.entity.attributesByName["isSoftDeleted"] != nil,
          let isDeleted = entity.value(forKey: "isSoftDeleted") as? Bool else {
        return false
    }
    return isDeleted
}

/// Helper function to add soft delete filter to a predicate
/// Returns a compound predicate that excludes soft-deleted items
func addSoftDeleteFilter(to predicate: NSPredicate?, entityName: String) -> NSPredicate {
    let softDeleteFilter = NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
    
    if let existing = predicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [existing, softDeleteFilter])
    } else {
        return softDeleteFilter
    }
}

/// Helper function to create a predicate that excludes soft-deleted items
func notSoftDeletedPredicate() -> NSPredicate {
    return NSPredicate(format: "isSoftDeleted != YES OR isSoftDeleted == nil")
}

