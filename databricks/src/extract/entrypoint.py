from rest_api import extract_to_volume
from dagster_pipes import (
    PipesCliArgsParamsLoader,
    PipesUnityCatalogVolumesContextLoader,
    PipesUnityCatalogVolumesMessageWriter,
    open_dagster_pipes,
)

with open_dagster_pipes(
    params_loader=PipesCliArgsParamsLoader(),
    context_loader=PipesUnityCatalogVolumesContextLoader(),
    message_writer=PipesUnityCatalogVolumesMessageWriter(),
) as pipes:
    auth_header = pipes.get_extra("auth_header", None)
    auth_value = pipes.get_extra("auth_value", None)
    auth = {auth_header: auth_value} if auth_header and auth_value else None

    metadata = extract_to_volume(
        pipes.get_extra("source_name"),
        pipes.get_extra("catalog"),
        auth_headers=auth,
    )
    pipes.report_asset_materialization(metadata=metadata)
