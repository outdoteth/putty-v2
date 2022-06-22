# Cancel

Cancels an order so that it cannot be filled in `fillOrder`.

## Diagram

```

                        checks
 input
 ┌──────────────┐       ┌───────────────────────────────────────────────────┐
 │ order: Order ├───────► *check sender is equal to order details creator   │
 └──────────────┘       └───────────────────────┬───────────────────────────┘
                                                │
                                                │
                         effects                │
                         ┌──────────────────────▼─────────────────┐
                         │ *mark hash(order details) as cancelled │
                         └────────────────────────────────────────┘
```
