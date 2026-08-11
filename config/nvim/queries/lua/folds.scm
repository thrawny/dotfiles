; Fold named and anonymous function bodies while keeping complete signatures and tables visible.
((function_declaration
  body: (block) @fold)
  (#offset! @fold 0 0 1 0))

((function_definition
  body: (block) @fold)
  (#offset! @fold 0 0 1 0))
