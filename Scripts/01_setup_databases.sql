
/*
Purpose:
- Resets the lab environment by dropping prior databases if they exist.
- Rebuilds the source database & admin database from scratch.
- Creates the source schema, indexes, & seed data.
- Sets OpsLab_Source to FULL recovery model so transaction log backups can be used later.

Run order:
1 of 7

Notes:
- Requires the C:\SQLLab\Data folder to exist.
- Uses explicit logical & physical file names for later RESTORE ... WITH MOVE testing.
- OpsLab_PITR cleanup uses RESTORE WITH RECOVERY first because a database in RESTORING state cannot be dropped with normal ALTER DATABASE logic. */

-- Clean up any existing lab databases from prior runs.
USE master;
GO

IF DB_ID(N'OpsLab_PITR') IS NOT NULL
BEGIN
    BEGIN TRY
        RESTORE DATABASE OpsLab_PITR WITH RECOVERY;
    END TRY
    BEGIN CATCH
        PRINT ERROR_MESSAGE();
    END CATCH;

    DROP DATABASE OpsLab_PITR;
END
GO

IF DB_ID(N'OpsLab_Restore') IS NOT NULL
BEGIN
    ALTER DATABASE OpsLab_Restore SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OpsLab_Restore;
END
GO

IF DB_ID(N'OpsLab_Source') IS NOT NULL
BEGIN
    ALTER DATABASE OpsLab_Source SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OpsLab_Source;
END
GO

IF DB_ID(N'OpsAdmin') IS NOT NULL
BEGIN
    ALTER DATABASE OpsAdmin SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OpsAdmin;
END
GO

-- Create the source database with explicit data & log file paths.
CREATE DATABASE OpsLab_Source
ON PRIMARY
(
    NAME = N'OpsLab_Source_Data',
    FILENAME = N'C:\SQLLab\Data\OpsLab_Source.mdf',
    SIZE = 16MB,
    FILEGROWTH = 16MB
)
LOG ON
(
    NAME = N'OpsLab_Source_Log',
    FILENAME = N'C:\SQLLab\Data\OpsLab_Source_log.ldf',
    SIZE = 16MB,
    FILEGROWTH = 16MB
);
GO

-- Switch the source database to FULL recovery model for PITR support.
ALTER DATABASE OpsLab_Source SET RECOVERY FULL;
GO

-- Create the admin database used for backup, restore, & validation logging.
CREATE DATABASE OpsAdmin
ON PRIMARY
(
    NAME = N'OpsAdmin_Data',
    FILENAME = N'C:\SQLLab\Data\OpsAdmin.mdf',
    SIZE = 16MB,
    FILEGROWTH = 16MB
)
LOG ON
(
    NAME = N'OpsAdmin_Log',
    FILENAME = N'C:\SQLLab\Data\OpsAdmin_log.ldf',
    SIZE = 16MB,
    FILEGROWTH = 16MB
);
GO

USE OpsLab_Source;
GO

-- Build the source schema used for backup & recovery testing.
CREATE TABLE dbo.customers
(
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,
    email      VARCHAR(100) NOT NULL UNIQUE,
    phone      VARCHAR(20) NULL,
    created_at DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.products
(
    product_id   INT IDENTITY(1,1) PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category     VARCHAR(50) NOT NULL,
    unit_price   DECIMAL(10,2) NOT NULL,
    is_active    BIT NOT NULL DEFAULT 1,
    created_at   DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.orders
(
    order_id      INT IDENTITY(1,1) PRIMARY KEY,
    customer_id   INT NOT NULL,
    order_date    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    order_status  VARCHAR(20) NOT NULL,
    total_amount  DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_orders_customers
        FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id)
);

CREATE TABLE dbo.order_items
(
    order_item_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id      INT NOT NULL,
    product_id    INT NOT NULL,
    quantity      INT NOT NULL,
    unit_price    DECIMAL(10,2) NOT NULL,
    line_total    DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_order_items_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id),
    CONSTRAINT FK_order_items_products
        FOREIGN KEY (product_id) REFERENCES dbo.products(product_id)
);

CREATE TABLE dbo.payments
(
    payment_id      INT IDENTITY(1,1) PRIMARY KEY,
    order_id        INT NOT NULL,
    payment_date    DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    payment_method  VARCHAR(30) NOT NULL,
    amount          DECIMAL(10,2) NOT NULL,
    payment_status  VARCHAR(20) NOT NULL,
    CONSTRAINT FK_payments_orders
        FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id)
);

CREATE TABLE dbo.audit_log
(
    audit_id          INT IDENTITY(1,1) PRIMARY KEY,
    entity_name       VARCHAR(50) NOT NULL,
    entity_id         INT NOT NULL,
    action_type       VARCHAR(20) NOT NULL,
    action_timestamp  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME(),
    changed_by        VARCHAR(50) NOT NULL
);

CREATE INDEX IX_orders_customer_id ON dbo.orders(customer_id);
CREATE INDEX IX_order_items_order_id ON dbo.order_items(order_id);
CREATE INDEX IX_order_items_product_id ON dbo.order_items(product_id);
CREATE INDEX IX_payments_order_id ON dbo.payments(order_id);
GO

-- Seed the source database with baseline data for restore validation & PITR testing.
INSERT INTO dbo.customers (first_name, last_name, email, phone) VALUES
('Michael', 'Mitchell', 'michael@example.com', '555-0101'),
('Sarah',   'Lopez',    'sarah@example.com',   '555-0102'),
('Daniel',  'Kim',      'daniel@example.com',  '555-0103'),
('Ashley',  'Brown',    'ashley@example.com',  '555-0104'),
('James',   'Carter',   'james@example.com',   '555-0105');

INSERT INTO dbo.products (product_name, category, unit_price, is_active) VALUES
('Laptop Dock',    'Hardware',    129.99, 1),
('Wireless Mouse', 'Hardware',     24.99, 1),
('USB-C Adapter',  'Accessories',  14.99, 1),
('Monitor 24 inch','Hardware',    179.99, 1),
('Keyboard',       'Hardware',     49.99, 1),
('VPN License',    'Software',     89.00, 1);

INSERT INTO dbo.orders (customer_id, order_date, order_status, total_amount) VALUES
(1, '2026-05-01T09:15:00', 'COMPLETED', 104.96),
(2, '2026-05-02T10:20:00', 'COMPLETED', 179.99),
(3, '2026-05-03T11:10:00', 'PENDING',    89.00),
(4, '2026-05-04T14:45:00', 'COMPLETED',  64.98),
(5, '2026-05-05T16:30:00', 'COMPLETED', 129.99);

INSERT INTO dbo.order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
(1, 2, 1, 24.99, 24.99),
(1, 5, 1, 49.99, 49.99),
(1, 3, 2, 14.99, 29.98),
(2, 4, 1, 179.99, 179.99),
(3, 6, 1, 89.00, 89.00),
(4, 2, 1, 24.99, 24.99),
(4, 5, 1, 39.99, 39.99),
(5, 1, 1, 129.99, 129.99);

INSERT INTO dbo.payments (order_id, payment_date, payment_method, amount, payment_status) VALUES
(1, '2026-05-01T09:30:00', 'CREDIT_CARD', 104.96, 'PAID'),
(2, '2026-05-02T10:35:00', 'CREDIT_CARD', 179.99, 'PAID'),
(3, '2026-05-03T11:20:00', 'PAYPAL',       89.00, 'PENDING'),
(4, '2026-05-04T15:00:00', 'DEBIT_CARD',   64.98, 'PAID'),
(5, '2026-05-05T16:45:00', 'CREDIT_CARD', 129.99, 'PAID');

INSERT INTO dbo.audit_log (entity_name, entity_id, action_type, changed_by) VALUES
('customers', 1, 'INSERT', 'system'),
('customers', 2, 'INSERT', 'system'),
('products',  1, 'INSERT', 'system'),
('orders',    1, 'INSERT', 'system'),
('payments',  1, 'INSERT', 'system');
GO