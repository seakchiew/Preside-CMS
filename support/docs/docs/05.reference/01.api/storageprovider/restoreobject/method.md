---
id: "storageprovider-restoreobject"
title: "restoreObject()"
---


## Overview




```luceescript
public boolean function restoreObject(
      required string  trashedPath
    , required string  newPath    
    ,          boolean private    
)
```

Restores an object that has been previously "trashed"/"Soft deleted".

## Arguments


<div class="table-responsive"><table class="table"><thead><tr><th>Name</th><th>Type</th><th>Required</th><th>Description</th></tr></thead><tbody><tr><td>trashedPath</td><td>string</td><td>Yes</td><td>Path of the stored object within the trash</td></tr><tr><td>newPath</td><td>string</td><td>Yes</td><td>Path to restore the object to</td></tr><tr><td>private</td><td>boolean</td><td>No</td><td>Whether or not the object should be restored to the private store</td></tr></tbody></table></div>