; Fold function bodies while keeping complete signatures and surrounding JSX declarations visible.
(function_declaration
  body: (statement_block) @fold)

(generator_function_declaration
  body: (statement_block) @fold)

(method_definition
  body: (statement_block) @fold)

(arrow_function
  body: (statement_block) @fold)

(function_expression
  body: (statement_block) @fold)

(generator_function
  body: (statement_block) @fold)
