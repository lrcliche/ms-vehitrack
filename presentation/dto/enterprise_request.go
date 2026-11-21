package dto

type EnterpriseRequestPoint struct {
	Address string   `json:"direccion" binding:"required,max=500"`
	Lat     *float64 `json:"lat" binding:"required"`
	Lng     *float64 `json:"lng" binding:"required"`
}

type CreateEnterpriseRequest struct {
	CustomerName  string                  `json:"nombre_cliente" binding:"required,min=1,max=200"`
	Origin        *EnterpriseRequestPoint `json:"origen" binding:"required"`
	Destination   *EnterpriseRequestPoint `json:"destino" binding:"required"`
	ScheduledAt   string                  `json:"fecha_servicio" binding:"required"`
	Passengers    int                     `json:"pasajeros" binding:"required,min=1"`
	AgreedFareCOP *float64                `json:"tarifa_pactada" binding:"required,gte=0"`
	Notes         string                  `json:"observaciones" binding:"omitempty,max=2000"`
}
