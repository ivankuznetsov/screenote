---
title: ApplicationRecord
type: model
source: app/models/application_record.rb
created: 2026-04-10
updated: 2026-04-10
tags: [model, base]
---

# ApplicationRecord

TLDR: Standard Rails abstract base class for all models. No custom additions.

Source: `app/models/application_record.rb`

## Definition

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
```

No custom validations, scopes, or methods added.
