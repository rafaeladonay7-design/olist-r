# Validación de calidad e integridad de datos · Olist (Brasil)
# Rafael Adonay Rocha Gutiérrez
#
# Revisa 8 tablas de pedidos de Olist con 32 reglas de calidad:
#   1. Completitud      datos faltantes donde no deberían faltar
#   2. Unicidad         llaves duplicadas
#   3. Integridad       registros que apuntan a algo que no existe
#   4. Fechas           fechas fuera de orden (p. ej. entregado antes de enviarse)
#   5. Estatus          estatus que no coincide con las fechas
#   6. Rangos           valores imposibles (precios en cero, calificaciones fuera de 1-5)
#   7. Cuadre           lo pagado no cuadra con el precio + envío
# Al final mide cuánto cambiaría un indicador de tablero (% de entregas tarde)
# si no se limpian los datos.
#
# Solo usa R base (sin paquetes). Ejecutar desde la carpeta del proyecto:
#   Rscript validacion.R

# ---------------------------------------------------------------------------
# 0. Cargar datos
# ---------------------------------------------------------------------------
# Los CSV de Kaggle van en la carpeta datos/ con su nombre original.
leer <- function(archivo) {
  read.csv(file.path("datos", archivo),
           na.strings = "", stringsAsFactors = FALSE, encoding = "UTF-8")
}

orders     <- leer("olist_orders_dataset.csv")
items      <- leer("olist_order_items_dataset.csv")
payments   <- leer("olist_order_payments_dataset.csv")
reviews    <- leer("olist_order_reviews_dataset.csv")
customers  <- leer("olist_customers_dataset.csv")
products   <- leer("olist_products_dataset.csv")
sellers    <- leer("olist_sellers_dataset.csv")
categorias <- leer("product_category_name_translation.csv")

filas <- c(orders = nrow(orders), order_items = nrow(items), payments = nrow(payments),
           reviews = nrow(reviews), customers = nrow(customers), products = nrow(products),
           sellers = nrow(sellers), category_translation = nrow(categorias))
cat("Registros cargados:\n"); print(filas)

# Fechas de texto a fecha-hora. Si un texto no es una fecha válida queda NA.
a_fecha <- function(x) as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")

compra    <- a_fecha(orders$order_purchase_timestamp)
aprobado  <- a_fecha(orders$order_approved_at)
paqueteria <- a_fecha(orders$order_delivered_carrier_date)
entregado <- a_fecha(orders$order_delivered_customer_date)
estimado  <- a_fecha(orders$order_estimated_delivery_date)

# ---------------------------------------------------------------------------
# Registro de reglas
# Cada regla guarda cuántos registros fallan y cuáles (para corregirlos).
# ---------------------------------------------------------------------------
reglas  <- data.frame()
detalle <- data.frame()

registrar <- function(categoria, tabla, regla, falla, ids, severidad) {
  falla <- falla & !is.na(falla)
  n <- sum(falla)
  reglas <<- rbind(reglas, data.frame(
    categoria = categoria, tabla = tabla, regla = regla,
    registros_revisados = length(falla), registros_con_problema = n,
    pct = round(100 * n / length(falla), 2), severidad = severidad))
  if (n > 0) {
    detalle <<- rbind(detalle, data.frame(tabla = tabla, regla = regla, id = ids[falla]))
  }
}

# ---------------------------------------------------------------------------
# 1. Completitud
# ---------------------------------------------------------------------------
registrar("Completitud", "orders", "Pedido sin fecha de aprobación",
          is.na(orders$order_approved_at) & orders$order_status != "canceled",
          orders$order_id, "Media")
registrar("Completitud", "products", "Producto sin categoría",
          is.na(products$product_category_name), products$product_id, "Media")
registrar("Completitud", "products", "Producto sin peso o medidas",
          is.na(products$product_weight_g) | is.na(products$product_length_cm) |
            is.na(products$product_height_cm) | is.na(products$product_width_cm),
          products$product_id, "Baja")
registrar("Completitud", "products", "Categoría sin traducción al inglés",
          !is.na(products$product_category_name) &
            !(products$product_category_name %in% categorias$product_category_name),
          products$product_id, "Baja")

# ---------------------------------------------------------------------------
# 2. Unicidad
# ---------------------------------------------------------------------------
registrar("Unicidad", "orders", "order_id duplicado",
          duplicated(orders$order_id), orders$order_id, "Alta")
registrar("Unicidad", "customers", "customer_id duplicado",
          duplicated(customers$customer_id), customers$customer_id, "Alta")
registrar("Unicidad", "products", "product_id duplicado",
          duplicated(products$product_id), products$product_id, "Alta")
registrar("Unicidad", "sellers", "seller_id duplicado",
          duplicated(sellers$seller_id), sellers$seller_id, "Alta")
registrar("Unicidad", "order_items", "Renglón de pedido duplicado (order_id + order_item_id)",
          duplicated(items[, c("order_id", "order_item_id")]), items$order_id, "Alta")
registrar("Unicidad", "payments", "Pago duplicado (order_id + payment_sequential)",
          duplicated(payments[, c("order_id", "payment_sequential")]), payments$order_id, "Alta")
registrar("Unicidad", "reviews", "review_id repetido en varios pedidos",
          duplicated(reviews$review_id) | duplicated(reviews$review_id, fromLast = TRUE),
          reviews$review_id, "Media")

# ---------------------------------------------------------------------------
# 3. Integridad referencial
# ---------------------------------------------------------------------------
registrar("Integridad", "orders", "Pedido con cliente inexistente",
          !(orders$customer_id %in% customers$customer_id), orders$order_id, "Alta")
registrar("Integridad", "order_items", "Renglón con pedido inexistente",
          !(items$order_id %in% orders$order_id), items$order_id, "Alta")
registrar("Integridad", "order_items", "Renglón con producto inexistente",
          !(items$product_id %in% products$product_id), items$order_id, "Alta")
registrar("Integridad", "order_items", "Renglón con vendedor inexistente",
          !(items$seller_id %in% sellers$seller_id), items$order_id, "Alta")
registrar("Integridad", "payments", "Pago de un pedido inexistente",
          !(payments$order_id %in% orders$order_id), payments$order_id, "Alta")
registrar("Integridad", "orders", "Pedido sin pago registrado",
          !(orders$order_id %in% payments$order_id), orders$order_id, "Media")
registrar("Integridad", "orders", "Pedido no cancelado sin productos",
          !(orders$order_id %in% items$order_id) &
            !(orders$order_status %in% c("canceled", "unavailable")),
          orders$order_id, "Media")

# ---------------------------------------------------------------------------
# 4. Fechas (orden cronológico)
# ---------------------------------------------------------------------------
registrar("Fechas", "orders", "Fecha de compra vacía o inválida",
          is.na(compra), orders$order_id, "Alta")
registrar("Fechas", "orders", "Aprobado antes de la compra",
          aprobado < compra, orders$order_id, "Alta")
registrar("Fechas", "orders", "Entregado a paquetería antes de la compra",
          paqueteria < compra, orders$order_id, "Alta")
registrar("Fechas", "orders", "Entregado al cliente antes de salir con paquetería",
          entregado < paqueteria, orders$order_id, "Alta")
registrar("Fechas", "orders", "Fecha estimada de entrega antes de la compra",
          estimado < compra, orders$order_id, "Alta")
registrar("Fechas", "reviews", "Respuesta de reseña antes de su creación",
          a_fecha(reviews$review_answer_timestamp) < a_fecha(reviews$review_creation_date),
          reviews$review_id, "Baja")

# ---------------------------------------------------------------------------
# 5. Estatus contra fechas
# ---------------------------------------------------------------------------
registrar("Estatus", "orders", "Estatus 'delivered' sin fecha de entrega",
          orders$order_status == "delivered" & is.na(entregado), orders$order_id, "Alta")
registrar("Estatus", "orders", "Pedido cancelado con fecha de entrega al cliente",
          orders$order_status == "canceled" & !is.na(entregado), orders$order_id, "Media")

# ---------------------------------------------------------------------------
# 6. Rangos
# ---------------------------------------------------------------------------
registrar("Rangos", "order_items", "Precio en cero o negativo",
          items$price <= 0, items$order_id, "Alta")
registrar("Rangos", "payments", "Pago en cero o negativo",
          payments$payment_value <= 0, payments$order_id, "Media")
registrar("Rangos", "payments", "Pago a 0 mensualidades",
          payments$payment_installments < 1, payments$order_id, "Baja")
registrar("Rangos", "reviews", "Calificación fuera de 1 a 5",
          !(reviews$review_score %in% 1:5), reviews$review_id, "Alta")
registrar("Rangos", "products", "Peso en cero",
          products$product_weight_g == 0, products$product_id, "Baja")

# ---------------------------------------------------------------------------
# 7. Cuadre: pagado contra precio + envío
# ---------------------------------------------------------------------------
cobrado <- aggregate(cbind(total = price + freight_value) ~ order_id, data = items, FUN = sum)
pagado  <- aggregate(payment_value ~ order_id, data = payments, FUN = sum)
cuadre  <- merge(cobrado, pagado, by = "order_id")
cuadre$diferencia <- round(cuadre$payment_value - cuadre$total, 2)
registrar("Cuadre", "payments", "Lo pagado no cuadra con precio + envío (> R$1)",
          abs(cuadre$diferencia) > 1, cuadre$order_id, "Media")

# ---------------------------------------------------------------------------
# Resultados
# ---------------------------------------------------------------------------
reglas <- reglas[order(-reglas$registros_con_problema), ]
rownames(reglas) <- NULL
write.csv(reglas, "resultados/reglas.csv", row.names = FALSE, fileEncoding = "UTF-8")
write.csv(detalle, "resultados/registros_con_problemas.csv", row.names = FALSE, fileEncoding = "UTF-8")

cat("\nReglas revisadas:", nrow(reglas),
    "| con problemas:", sum(reglas$registros_con_problema > 0), "\n\n")
print(reglas[, c("categoria", "regla", "registros_con_problema", "pct", "severidad")])

# Gráfica: reglas con problemas
con_problema <- reglas[reglas$registros_con_problema > 0, ]
con_problema <- con_problema[order(con_problema$registros_con_problema), ]
colores <- c(Alta = "#c0392b", Media = "#e67e22", Baja = "#95a5a6")

png("figuras/problemas_por_regla.png", width = 1400, height = 120 + 55 * nrow(con_problema), res = 150)
par(mar = c(4, 24, 2, 5))
pos <- barplot(con_problema$registros_con_problema, horiz = TRUE, las = 1,
               names.arg = con_problema$regla, col = colores[con_problema$severidad],
               border = NA, cex.names = 0.75, xlab = "Registros con problema",
               xlim = c(0, max(con_problema$registros_con_problema) * 1.15))
text(con_problema$registros_con_problema, pos, format(con_problema$registros_con_problema, big.mark = ","),
     pos = 4, cex = 0.7, xpd = TRUE)
legend("bottomright", legend = names(colores), fill = colores, border = NA,
       title = "Severidad", cex = 0.75, bty = "n")
invisible(dev.off())

# ---------------------------------------------------------------------------
# Impacto en un tablero: % de entregas tarde
# Un tablero que calcula el % de pedidos entregados tarde con los datos crudos
# contra el mismo cálculo después de quitar los pedidos con fechas inválidas.
# ---------------------------------------------------------------------------
entregados <- orders$order_status == "delivered"
tarde      <- entregado > estimado

crudo_den  <- sum(entregados)
crudo_num  <- sum(entregados & tarde, na.rm = TRUE)

fechas_malas <- unique(detalle$id[detalle$tabla == "orders" &
                                  detalle$regla %in% c("Estatus 'delivered' sin fecha de entrega",
                                                       "Entregado al cliente antes de salir con paquetería",
                                                       "Entregado a paquetería antes de la compra",
                                                       "Aprobado antes de la compra")])
validos    <- entregados & !(orders$order_id %in% fechas_malas)
limpio_num <- sum(validos & tarde, na.rm = TRUE)
limpio_den <- sum(validos)

impacto <- data.frame(
  version = c("Datos crudos", "Datos validados"),
  pedidos_entregados = c(crudo_den, limpio_den),
  entregados_tarde = c(crudo_num, limpio_num),
  pct_tarde = round(100 * c(crudo_num / crudo_den, limpio_num / limpio_den), 2))
write.csv(impacto, "resultados/impacto_tablero.csv", row.names = FALSE)
cat("\nImpacto en el indicador '% de entregas tarde':\n"); print(impacto)

# Tiempo de entrega promedio: negativo o inflado por fechas fuera de orden
dias <- as.numeric(difftime(entregado, paqueteria, units = "days"))
cat("\nPedidos con tiempo de paquetería negativo:", sum(dias < 0, na.rm = TRUE), "\n")

# Ventas sin categoría: en un tablero de ventas por categoría este dinero
# aparece como "(en blanco)" o desaparece del filtro.
items_cat <- merge(items, products[, c("product_id", "product_category_name")], by = "product_id", all.x = TRUE)
venta_total <- sum(items_cat$price)
venta_sin_cat <- sum(items_cat$price[is.na(items_cat$product_category_name)])
cat("Ventas de productos sin categoría: R$", format(round(venta_sin_cat), big.mark = ","),
    " (", round(100 * venta_sin_cat / venta_total, 2), "% de las ventas)\n", sep = "")

# Reseñas: contar por review_id en lugar de por renglón subestima las reseñas
cat("Reseñas por renglón:", nrow(reviews), "| por review_id único:", length(unique(reviews$review_id)), "\n")
