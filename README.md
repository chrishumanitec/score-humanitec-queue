# Simulate Score Artefact

Individual CI pipelines should be able to push both an Image and a Score file to Humanitec. The update should either be immediatly deployed, or if there is another deployment ongoing, it should build a delta.

This should work for any number of CI runs running almost simultaniously.


