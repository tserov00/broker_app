--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: able_to_sell(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.able_to_sell(p_security_id integer, p_quantity integer, p_customer_account_id integer) RETURNS boolean
    LANGUAGE sql
    AS $$
SELECT COALESCE(
               (SELECT total_quantity >= p_quantity
                FROM customer_portfolios
                WHERE customer_account_id = p_customer_account_id
                  AND security_id = p_security_id),
               FALSE
       );
$$;


ALTER FUNCTION public.able_to_sell(p_security_id integer, p_quantity integer, p_customer_account_id integer) OWNER TO postgres;

--
-- Name: block_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.block_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
--     RAISE EXCEPTION 'DELETE on table "%" is not allowed', TG_TABLE_NAME;
--     RETURN NULL;
END;
$$;


ALTER FUNCTION public.block_delete() OWNER TO postgres;

--
-- Name: block_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.block_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'INSERT on table "%" is not allowed', TG_TABLE_NAME;
    -- Можно вернуть NULL, но при RAISE EXCEPTION выполнение и так прервётся
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.block_insert() OWNER TO postgres;

--
-- Name: block_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.block_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'UPDATE on table "%" is not allowed', TG_TABLE_NAME;
    RETURN NULL;
END;
$$;


ALTER FUNCTION public.block_update() OWNER TO postgres;

--
-- Name: calculate_broker_fee(numeric, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_broker_fee(price numeric, quantity integer) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT price * quantity * 0.003;
$$;


ALTER FUNCTION public.calculate_broker_fee(price numeric, quantity integer) OWNER TO postgres;

--
-- Name: cancel_order(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancel_order(p_order_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
DECLARE
    v_order_type_id int;
    v_available_quantity int;
    v_price decimal(10,2);
    v_fee decimal(12,5);
    v_customer_account_id int;
    v_security_id int;
    v_savings_account_id int;
BEGIN
    -- Получаем данные ордера
    SELECT order_type_id, available_quantity, price, fee, customer_account_id, security_id, savings_account_id
    INTO v_order_type_id, v_available_quantity, v_price, v_fee, v_customer_account_id, v_security_id, v_savings_account_id
    FROM orders
    WHERE id = p_order_id;

    -- Проверяем, существует ли ордер
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ордер с id % не найден', p_order_id;
    END IF;

    -- Обновляем таблицу orders: устанавливаем статус "canceled" и available_quantity = NULL
    UPDATE orders
    SET order_status_id = 4,
        available_quantity = NULL
    WHERE id = p_order_id;

    -- В зависимости от типа ордера обновляем соответствующую таблицу
    IF v_order_type_id = 1 THEN
        -- Ордер на покупку (buy): уменьшаем reserved_amount в savings_accounts
        UPDATE savings_accounts
        SET reserved_amount = reserved_amount - (v_price * v_available_quantity + v_fee)
        WHERE id = v_savings_account_id;
    ELSIF v_order_type_id = 2 THEN
        -- Ордер на продажу (sell): уменьшаем reserved_quantity в customer_portfolios
        UPDATE customer_portfolios
        SET reserved_quantity = reserved_quantity - v_available_quantity
        WHERE customer_account_id = v_customer_account_id
          AND security_id = v_security_id;
    ELSE
        RAISE EXCEPTION 'Недопустимый тип ордера: %', v_order_type_id;
    END IF;
END;
$$;


ALTER FUNCTION public.cancel_order(p_order_id integer) OWNER TO postgres;

--
-- Name: create_buy_order(integer, numeric, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_buy_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
DECLARE
    v_fee numeric(12,5);
    v_currency_match boolean;
    v_customer_account_id integer;
BEGIN
    -- Извлечение customer_account_id из savings_accounts
    SELECT customer_account_id INTO v_customer_account_id
    FROM savings_accounts
    WHERE id = p_savings_account_id;

    -- Проверка, что savings_account_id существует
    IF v_customer_account_id IS NULL THEN
        RAISE EXCEPTION 'Savings account with id % does not exist', p_savings_account_id;
    END IF;

    -- Проверка совпадения валюты счета и ценной бумаги
    SELECT savings_account_check(p_savings_account_id, p_security_id) INTO v_currency_match;
    IF NOT v_currency_match THEN
        RAISE EXCEPTION 'Currency mismatch between savings account and security';
    END IF;

    -- Вычисление комиссии брокера
    SELECT calculate_broker_fee(p_price, p_quantity) INTO v_fee;

    -- Резервирование суммы на счете
    UPDATE savings_accounts
    SET reserved_amount = reserved_amount + (p_price * p_quantity + v_fee)
    WHERE id = p_savings_account_id;

    -- Создание ордера на покупку
    INSERT INTO orders (
        customer_account_id,
        security_id,
        savings_account_id,
        price,
        fee,
        quantity,
        available_quantity,
        created_at,
        order_type_id,
        order_status_id
    )
    VALUES (
               v_customer_account_id,
               p_security_id,
               p_savings_account_id,
               p_price,
               v_fee,
               p_quantity,
               p_quantity,
               now(),
               1,
               1
           );
END;
$$;


ALTER PROCEDURE public.create_buy_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer) OWNER TO postgres;

--
-- Name: create_sell_order(integer, numeric, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.create_sell_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
DECLARE
    v_fee numeric(12,5);
    v_currency_match boolean;
    v_customer_account_id integer;
    v_able_to_sell boolean;
BEGIN
    -- Извлечение customer_account_id из savings_accounts
    SELECT customer_account_id INTO v_customer_account_id
    FROM savings_accounts
    WHERE id = p_savings_account_id;

    -- Проверка, что savings_account_id существует
    IF v_customer_account_id IS NULL THEN
        RAISE EXCEPTION 'Savings account with id % does not exist', p_savings_account_id;
    END IF;

    -- Проверка достаточности ценных бумаг для продажи
    SELECT able_to_sell(p_security_id, p_quantity, v_customer_account_id) INTO v_able_to_sell;
    IF NOT v_able_to_sell THEN
        RAISE EXCEPTION 'Insufficient securities to sell for customer_account_id % and security_id %', v_customer_account_id, p_security_id;
    END IF;

    -- Проверка совпадения валюты счета и ценной бумаги
    SELECT savings_account_check(p_savings_account_id, p_security_id) INTO v_currency_match;
    IF NOT v_currency_match THEN
        RAISE EXCEPTION 'Currency mismatch between savings account and security';
    END IF;

    -- Вычисление комиссии брокера
    SELECT calculate_broker_fee(p_price, p_quantity) INTO v_fee;

    -- Резервирование количества в портфеле
    UPDATE customer_portfolios
    SET reserved_quantity = reserved_quantity + p_quantity
    WHERE customer_account_id = v_customer_account_id
      AND security_id = p_security_id;

    -- Создание ордера на продажу
    INSERT INTO orders (
        customer_account_id,
        security_id,
        savings_account_id,
        price,
        fee,
        quantity,
        available_quantity,
        created_at,
        order_type_id,
        order_status_id
    )
    VALUES (
               v_customer_account_id,
               p_security_id,
               p_savings_account_id,
               p_price,
               v_fee,
               p_quantity,
               p_quantity,
               now(),
               2,  -- Предполагается, что 2 — это тип ордера на продажу
               1   -- Предполагается, что 1 — это статус "created"
           );
END;
$$;


ALTER PROCEDURE public.create_sell_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer) OWNER TO postgres;

--
-- Name: deposit_balance(numeric, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.deposit_balance(IN p_amount numeric, IN p_savings_account_id integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
DECLARE
    row_count INTEGER;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be positive';
    END IF;

    UPDATE savings_accounts
    SET balance = balance + p_amount
    WHERE id = p_savings_account_id;

    GET DIAGNOSTICS row_count = ROW_COUNT;

    IF row_count = 0 THEN
        RAISE EXCEPTION 'Savings account with id % does not exist', p_savings_account_id;
    END IF;

    INSERT INTO balance_history (savings_account_id, transaction_date, amount, transaction_type)
    VALUES (p_savings_account_id, now(), p_amount, 1);
END;
$$;


ALTER PROCEDURE public.deposit_balance(IN p_amount numeric, IN p_savings_account_id integer) OWNER TO postgres;

--
-- Name: execute_transaction(integer, integer, numeric); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.execute_transaction(IN buy_order_id integer, IN sell_order_id integer, IN executed_price numeric)
    LANGUAGE plpgsql
    AS $$
DECLARE
    buyer_id int;
    buy_security_id int;
    buyer_savings_account_id int;
    available_quantity_buy int;
    seller_id int;
    sell_security_id int;
    seller_savings_account_id int;
    available_quantity_sell int;
    transaction_quantity int;
    executed_fee decimal(12,5);
    old_qty int;
    old_avg decimal(10,2);
BEGIN
    -- Получаем данные о заказе на покупку
    SELECT customer_account_id, security_id, savings_account_id, available_quantity, price
    INTO buyer_id, buy_security_id, buyer_savings_account_id, available_quantity_buy
    FROM orders
    WHERE id = buy_order_id;

    -- Получаем данные о заказе на продажу
    SELECT customer_account_id, security_id, savings_account_id, available_quantity
    INTO seller_id, sell_security_id, seller_savings_account_id, available_quantity_sell
    FROM orders
    WHERE id = sell_order_id;

    -- Проверяем совпадение security_id
    IF buy_security_id <> sell_security_id THEN
        RAISE EXCEPTION 'Security ID mismatch between buy and sell orders';
    END IF;

    -- Вычисляем количество для транзакции как минимум из доступных количеств
    transaction_quantity := LEAST(available_quantity_buy, available_quantity_sell);

    -- Вычисляем общую комиссию брокера за транзакцию для каждого участника
    executed_fee := calculate_broker_fee(executed_price, transaction_quantity);

    -- Обновляем портфель и счёт продавца
    UPDATE customer_portfolios
    SET reserved_quantity = reserved_quantity - transaction_quantity,
        total_quantity = total_quantity - transaction_quantity,
        sold_quantity = COALESCE(sold_quantity, 0) + transaction_quantity,
        avg_sell_price = (COALESCE(avg_sell_price * sold_quantity, 0) + executed_price * transaction_quantity - executed_fee) /
                         (COALESCE(sold_quantity, 0) + transaction_quantity)
    WHERE customer_account_id = seller_id AND security_id = sell_security_id;

    UPDATE savings_accounts
    SET balance = balance + (executed_price * transaction_quantity - executed_fee)
    WHERE id = seller_savings_account_id;

    -- Обновляем счёт покупателя
    UPDATE savings_accounts
    SET balance = balance - (executed_price * transaction_quantity + executed_fee),
        reserved_amount = reserved_amount - (executed_price * transaction_quantity + executed_fee)
    WHERE id = buyer_savings_account_id;

    -- Обновляем или добавляем запись в портфель покупателя
    SELECT total_quantity, avg_buy_price
    INTO old_qty, old_avg
    FROM customer_portfolios
    WHERE customer_account_id = buyer_id AND security_id = buy_security_id
        FOR UPDATE;

    IF FOUND THEN
        UPDATE customer_portfolios
        SET total_quantity = old_qty + transaction_quantity,
            avg_buy_price = (old_avg * old_qty + executed_price * transaction_quantity + executed_fee) / (old_qty + transaction_quantity)
        WHERE customer_account_id = buyer_id AND security_id = buy_security_id;
    ELSE
        INSERT INTO customer_portfolios (customer_account_id, security_id, total_quantity, reserved_quantity, avg_buy_price)
        VALUES (buyer_id, buy_security_id, transaction_quantity, 0, (executed_price + executed_fee / transaction_quantity));
    END IF;

    -- Обновляем статус и количество для заказа на покупку
    UPDATE orders
    SET available_quantity = CASE WHEN available_quantity - transaction_quantity > 0 THEN available_quantity - transaction_quantity ELSE NULL END,
        order_status_id = CASE WHEN available_quantity - transaction_quantity > 0 THEN 3 ELSE 2 END
    WHERE id = buy_order_id;

    -- Обновляем статус и количество для заказа на продажу
    UPDATE orders
    SET available_quantity = CASE WHEN available_quantity - transaction_quantity > 0 THEN available_quantity - transaction_quantity ELSE NULL END,
        order_status_id = CASE WHEN available_quantity - transaction_quantity > 0 THEN 3 ELSE 2 END
    WHERE id = sell_order_id;

    -- Логируем транзакцию
    INSERT INTO transactions (buy_order_id, sell_order_id, quantity, executed_price, executed_fee)
    VALUES (buy_order_id, sell_order_id, transaction_quantity, executed_price, executed_fee);
END;
$$;


ALTER PROCEDURE public.execute_transaction(IN buy_order_id integer, IN sell_order_id integer, IN executed_price numeric) OWNER TO postgres;

--
-- Name: generate_savings_account_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_savings_account_number() RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
    account_number varchar(30);
    length int;
    i int;
    digit int;
    exists boolean;
BEGIN
    -- Генерируем случайную длину от 10 до 30
    length := 10 + floor(random() * 21)::int;

    LOOP
        account_number := '';
        -- Генерируем случайный номер заданной длины
        FOR i IN 1..length LOOP
                digit := floor(random() * 10)::int;
                account_number := account_number || digit::varchar;
            END LOOP;

        -- Проверяем, существует ли уже такой номер
        SELECT EXISTS (
            SELECT 1 FROM savings_accounts WHERE savings_account_number = account_number
        ) INTO exists;

        -- Если номер уникален, выходим из цикла
        IF NOT exists THEN
            EXIT;
        END IF;
    END LOOP;

    RETURN account_number;
END;
$$;


ALTER FUNCTION public.generate_savings_account_number() OWNER TO postgres;

--
-- Name: get_most_profitable_deal(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_most_profitable_deal(user_id integer) RETURNS TABLE(customer_account_id integer, security_id integer, avg_buy_price numeric, total_quantity integer, last_price numeric, unrealized_profit numeric)
    LANGUAGE sql
    AS $$
SELECT
    cp.customer_account_id,
    cp.security_id,
    cp.avg_buy_price,
    cp.total_quantity,
    s.last_price,
    (s.last_price - cp.avg_buy_price) * cp.total_quantity AS unrealized_profit
FROM
    customer_portfolios cp
        JOIN
    securities s ON cp.security_id = s.id
        JOIN
    customer_accounts ca ON cp.customer_account_id = ca.id
WHERE
    ca.customer_id = user_id
  AND s.last_price > cp.avg_buy_price
ORDER BY
    (s.last_price - cp.avg_buy_price) DESC
LIMIT 1;
$$;


ALTER FUNCTION public.get_most_profitable_deal(user_id integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    id integer NOT NULL,
    customer_account_id integer NOT NULL,
    security_id integer NOT NULL,
    savings_account_id integer NOT NULL,
    price numeric(10,2) NOT NULL,
    fee numeric(12,5) NOT NULL,
    quantity integer NOT NULL,
    available_quantity integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    order_type_id integer NOT NULL,
    order_status_id integer NOT NULL
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- Name: get_open_orders_with_large_price_difference(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_open_orders_with_large_price_difference(user_id integer) RETURNS SETOF public.orders
    LANGUAGE sql
    AS $$
SELECT o.*
FROM orders o
         JOIN securities s ON o.security_id = s.id
WHERE o.customer_account_id = user_id
  AND o.available_quantity > 0
  AND s.last_price > 0
  AND ABS(o.price - s.last_price) / s.last_price > 0.5;
$$;


ALTER FUNCTION public.get_open_orders_with_large_price_difference(user_id integer) OWNER TO postgres;

--
-- Name: match_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.match_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    opposite_order RECORD;
    executed_price decimal(10,2);
BEGIN
    IF NEW.order_type_id = 1 THEN  -- Buy order
        SELECT * INTO opposite_order
        FROM orders
        WHERE order_type_id = 2  -- Sell order
          AND (order_status_id = 1 OR order_status_id = 3)  -- Open or Partially Executed
          AND price <= NEW.price
          AND security_id = NEW.security_id
        ORDER BY created_at ASC  -- FIFO
            FOR UPDATE;

        IF FOUND THEN
            executed_price := opposite_order.price;
            CALL execute_transaction(NEW.id, opposite_order.id, executed_price);
        END IF;
    ELSIF NEW.order_type_id = 2 THEN  -- Sell order
        SELECT * INTO opposite_order
        FROM orders
        WHERE order_type_id = 1  -- Buy order
          AND (order_status_id = 1 OR order_status_id = 3)  -- Open or Partially Executed
          AND price >= NEW.price
          AND security_id = NEW.security_id
        ORDER BY created_at ASC  -- FIFO
            FOR UPDATE;

        IF FOUND THEN
            executed_price := opposite_order.price;
            CALL execute_transaction(opposite_order.id, NEW.id, executed_price);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.match_order() OWNER TO postgres;

--
-- Name: savings_account_check(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.savings_account_check(savings_account_id integer, security_id integer) RETURNS boolean
    LANGUAGE sql
    AS $$
SELECT EXISTS (
    SELECT 1
    FROM savings_accounts sa
             JOIN securities s ON sa.currency_id = s.currency_id
    WHERE sa.id = savings_account_id AND s.id = security_id
);
$$;


ALTER FUNCTION public.savings_account_check(savings_account_id integer, security_id integer) OWNER TO postgres;

--
-- Name: withdraw_balance(numeric, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.withdraw_balance(IN p_amount numeric, IN p_savings_account_id integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
DECLARE
    current_balance DECIMAL(15,2);
    current_reserved_amount DECIMAL(15,2);
BEGIN
    -- Check if the withdrawal amount is positive
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be positive';
    END IF;

    -- Retrieve current balance and reserved amount, treating NULL reserved_amount as 0
    SELECT balance, COALESCE(reserved_amount, 0) INTO current_balance, current_reserved_amount
    FROM savings_accounts
    WHERE id = p_savings_account_id;

    -- Check if the account exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Savings account with id % does not exist', p_savings_account_id;
    END IF;

    -- Check if withdrawal would result in a negative balance
    IF current_balance - p_amount < 0 THEN
        RAISE EXCEPTION 'Insufficient funds: withdrawal would result in negative balance';
    END IF;

    -- Check if withdrawal would violate the reserved amount constraint
    IF current_balance - p_amount <= current_reserved_amount THEN
        RAISE EXCEPTION 'Insufficient funds: withdrawal would violate reserved amount constraint';
    END IF;

    -- Update the balance in savings_accounts
    UPDATE savings_accounts
    SET balance = balance - p_amount
    WHERE id = p_savings_account_id;

    -- Insert a record into balance_history with transaction_type = 2 (withdrawal)
    INSERT INTO balance_history (savings_account_id, transaction_date, amount, transaction_type)
    VALUES (p_savings_account_id, now(), p_amount, 2);
END;
$$;


ALTER PROCEDURE public.withdraw_balance(IN p_amount numeric, IN p_savings_account_id integer) OWNER TO postgres;

--
-- Name: balance_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.balance_history (
    id integer NOT NULL,
    savings_account_id integer NOT NULL,
    transaction_date timestamp without time zone DEFAULT now(),
    amount numeric(15,2) NOT NULL,
    transaction_type integer NOT NULL
);


ALTER TABLE public.balance_history OWNER TO postgres;

--
-- Name: balance_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.balance_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.balance_history_id_seq OWNER TO postgres;

--
-- Name: balance_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.balance_history_id_seq OWNED BY public.balance_history.id;


--
-- Name: bond_payment_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bond_payment_types (
    id integer NOT NULL,
    payment_type character varying(30) NOT NULL
);


ALTER TABLE public.bond_payment_types OWNER TO postgres;

--
-- Name: bonds; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bonds (
    id integer NOT NULL,
    maturity_date date NOT NULL,
    coupon_rate numeric(5,2) NOT NULL,
    face_value numeric(10,2) NOT NULL,
    issue_date date NOT NULL,
    amortization boolean NOT NULL,
    CONSTRAINT bonds_face_value_check CHECK ((face_value >= (0)::numeric))
);


ALTER TABLE public.bonds OWNER TO postgres;

--
-- Name: bonds_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bonds_payments (
    id integer NOT NULL,
    bond_id integer NOT NULL,
    payment_type integer NOT NULL,
    payment_date date NOT NULL,
    payment_amount numeric(10,2) NOT NULL,
    currency_id integer NOT NULL,
    CONSTRAINT bonds_payments_payment_amount_check CHECK ((payment_amount >= (0)::numeric))
);


ALTER TABLE public.bonds_payments OWNER TO postgres;

--
-- Name: bonds_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bonds_payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bonds_payments_id_seq OWNER TO postgres;

--
-- Name: bonds_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bonds_payments_id_seq OWNED BY public.bonds_payments.id;


--
-- Name: currencies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.currencies (
    id integer NOT NULL,
    code character varying(3) NOT NULL
);


ALTER TABLE public.currencies OWNER TO postgres;

--
-- Name: currencies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.currencies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.currencies_id_seq OWNER TO postgres;

--
-- Name: currencies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.currencies_id_seq OWNED BY public.currencies.id;


--
-- Name: customer_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_accounts (
    id integer NOT NULL,
    customer_id integer NOT NULL,
    phone_number character varying(20) NOT NULL,
    email character varying(100) NOT NULL,
    login character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL
);


ALTER TABLE public.customer_accounts OWNER TO postgres;

--
-- Name: customer_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customer_accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customer_accounts_id_seq OWNER TO postgres;

--
-- Name: customer_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customer_accounts_id_seq OWNED BY public.customer_accounts.id;


--
-- Name: customer_portfolios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customer_portfolios (
    customer_account_id integer NOT NULL,
    security_id integer NOT NULL,
    total_quantity integer NOT NULL,
    reserved_quantity integer DEFAULT 0 NOT NULL,
    avg_buy_price numeric(15,6) DEFAULT 0 NOT NULL,
    avg_sell_price numeric(18,5) DEFAULT NULL::numeric,
    sold_quantity integer,
    CONSTRAINT customer_portfolios_check CHECK ((total_quantity >= reserved_quantity)),
    CONSTRAINT customer_portfolios_total_quantity_check CHECK ((total_quantity >= 0))
);


ALTER TABLE public.customer_portfolios OWNER TO postgres;

--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    date_of_birth date NOT NULL,
    passport_series character varying(30) NOT NULL,
    address character varying(255),
    tax_id character varying(30) NOT NULL
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_id_seq OWNER TO postgres;

--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: order_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_status (
    id integer NOT NULL,
    status character varying(18) NOT NULL
);


ALTER TABLE public.order_status OWNER TO postgres;

--
-- Name: order_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_type (
    id integer NOT NULL,
    type character varying(4) NOT NULL
);


ALTER TABLE public.order_type OWNER TO postgres;

--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.orders_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_id_seq OWNER TO postgres;

--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: realized_profit_by_security_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.realized_profit_by_security_view AS
 SELECT customer_account_id,
    security_id,
    COALESCE(sold_quantity, 0) AS sold_quantity,
    COALESCE(avg_sell_price, (0)::numeric) AS avg_sell_price,
    avg_buy_price,
    ((COALESCE(avg_sell_price, (0)::numeric) - avg_buy_price) * (COALESCE(sold_quantity, 0))::numeric) AS realized_profit
   FROM public.customer_portfolios cp
  WHERE ((sold_quantity IS NOT NULL) AND (sold_quantity > 0));


ALTER VIEW public.realized_profit_by_security_view OWNER TO postgres;

--
-- Name: savings_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.savings_accounts (
    id integer NOT NULL,
    customer_account_id integer NOT NULL,
    savings_account_number character varying(30) NOT NULL,
    currency_id integer NOT NULL,
    balance numeric(15,2) NOT NULL,
    reserved_amount numeric(19,5) DEFAULT 0 NOT NULL,
    CONSTRAINT savings_accounts_balance_check CHECK ((balance >= (0)::numeric)),
    CONSTRAINT savings_accounts_check CHECK ((balance >= reserved_amount))
);


ALTER TABLE public.savings_accounts OWNER TO postgres;

--
-- Name: savings_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.savings_accounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.savings_accounts_id_seq OWNER TO postgres;

--
-- Name: savings_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.savings_accounts_id_seq OWNED BY public.savings_accounts.id;


--
-- Name: securities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.securities (
    id integer NOT NULL,
    security_type integer NOT NULL,
    ticker character varying(20) NOT NULL,
    isin character varying(12) NOT NULL,
    company_name character varying(100) NOT NULL,
    stock_exchange integer NOT NULL,
    currency_id integer NOT NULL,
    last_price numeric(10,2) NOT NULL,
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT securities_last_price_check CHECK ((last_price >= (0)::numeric))
);


ALTER TABLE public.securities OWNER TO postgres;

--
-- Name: securities_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.securities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.securities_id_seq OWNER TO postgres;

--
-- Name: securities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.securities_id_seq OWNED BY public.securities.id;


--
-- Name: security_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.security_types (
    id integer NOT NULL,
    security_type character varying(10) NOT NULL
);


ALTER TABLE public.security_types OWNER TO postgres;

--
-- Name: stock_exchanges; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock_exchanges (
    id integer NOT NULL,
    stock_exchange character varying(50) NOT NULL
);


ALTER TABLE public.stock_exchanges OWNER TO postgres;

--
-- Name: stocks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stocks (
    id integer NOT NULL,
    dividend_declaration_date date,
    ex_dividend_date date,
    divident_payment_date date,
    divident_amount numeric(10,2),
    dividend_currency_id integer
);


ALTER TABLE public.stocks OWNER TO postgres;

--
-- Name: unrealized_profit_by_security_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.unrealized_profit_by_security_view AS
 SELECT cp.customer_account_id,
    cp.security_id,
    cp.total_quantity,
    cp.avg_buy_price,
    s.last_price,
    (((s.last_price * (cp.total_quantity)::numeric) - public.calculate_broker_fee(s.last_price, cp.total_quantity)) - (cp.avg_buy_price * (cp.total_quantity)::numeric)) AS profit
   FROM (public.customer_portfolios cp
     JOIN public.securities s ON ((s.id = cp.security_id)));


ALTER VIEW public.unrealized_profit_by_security_view OWNER TO postgres;

--
-- Name: total_profit_by_security; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.total_profit_by_security AS
 SELECT COALESCE(r.customer_account_id, u.customer_account_id) AS customer_account_id,
    COALESCE(r.security_id, u.security_id) AS security_id,
    (COALESCE(r.realized_profit, (0)::numeric) + COALESCE(u.profit, (0)::numeric)) AS total_profit
   FROM (public.realized_profit_by_security_view r
     FULL JOIN public.unrealized_profit_by_security_view u USING (customer_account_id, security_id));


ALTER VIEW public.total_profit_by_security OWNER TO postgres;

--
-- Name: total_profit_by_portfolio; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.total_profit_by_portfolio AS
 SELECT customer_account_id,
    sum(total_profit) AS sum
   FROM public.total_profit_by_security
  GROUP BY customer_account_id;


ALTER VIEW public.total_profit_by_portfolio OWNER TO postgres;

--
-- Name: total_realized_profit; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.total_realized_profit AS
 SELECT customer_account_id,
    sum(realized_profit) AS total_realized_profit
   FROM public.realized_profit_by_security_view
  GROUP BY customer_account_id;


ALTER VIEW public.total_realized_profit OWNER TO postgres;

--
-- Name: total_unrealized_profit; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.total_unrealized_profit AS
 SELECT customer_account_id,
    sum(profit) AS sum
   FROM public.unrealized_profit_by_security_view
  GROUP BY customer_account_id;


ALTER VIEW public.total_unrealized_profit OWNER TO postgres;

--
-- Name: transaction_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transaction_types (
    id integer NOT NULL,
    transaction_type character varying(10) NOT NULL
);


ALTER TABLE public.transaction_types OWNER TO postgres;

--
-- Name: transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transactions (
    id integer NOT NULL,
    buy_order_id integer NOT NULL,
    sell_order_id integer NOT NULL,
    quantity integer NOT NULL,
    executed_price numeric(10,2) NOT NULL,
    executed_fee numeric(12,5) NOT NULL,
    executed_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.transactions OWNER TO postgres;

--
-- Name: transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.transactions_id_seq OWNER TO postgres;

--
-- Name: transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.transactions_id_seq OWNED BY public.transactions.id;


--
-- Name: balance_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.balance_history ALTER COLUMN id SET DEFAULT nextval('public.balance_history_id_seq'::regclass);


--
-- Name: bonds_payments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds_payments ALTER COLUMN id SET DEFAULT nextval('public.bonds_payments_id_seq'::regclass);


--
-- Name: currencies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.currencies ALTER COLUMN id SET DEFAULT nextval('public.currencies_id_seq'::regclass);


--
-- Name: customer_accounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_accounts ALTER COLUMN id SET DEFAULT nextval('public.customer_accounts_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: savings_accounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts ALTER COLUMN id SET DEFAULT nextval('public.savings_accounts_id_seq'::regclass);


--
-- Name: securities id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities ALTER COLUMN id SET DEFAULT nextval('public.securities_id_seq'::regclass);


--
-- Name: transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions ALTER COLUMN id SET DEFAULT nextval('public.transactions_id_seq'::regclass);


--
-- Data for Name: balance_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.balance_history (id, savings_account_id, transaction_date, amount, transaction_type) FROM stdin;
1	1	2025-05-06 11:31:29.313029	41113.81	1
2	2	2025-05-06 11:31:29.313029	29116.87	1
3	3	2025-05-06 11:31:29.313029	54910.03	1
4	4	2025-05-06 11:31:29.313029	80218.77	1
5	5	2025-05-06 11:31:29.313029	95207.18	1
6	6	2025-05-06 11:31:29.313029	92741.05	1
7	7	2025-05-06 11:31:29.313029	81618.66	1
8	8	2025-05-06 11:31:29.313029	32500.89	1
9	9	2025-05-06 11:31:29.313029	54199.72	1
10	10	2025-05-06 11:31:29.313029	36904.98	1
11	11	2025-05-06 11:31:29.313029	40472.82	1
12	12	2025-05-06 11:31:29.313029	37520.09	1
13	13	2025-05-06 11:31:29.313029	67597.31	1
14	14	2025-05-06 11:31:29.313029	78966.25	1
15	15	2025-05-06 11:31:29.313029	26580.49	1
16	16	2025-05-06 11:31:29.313029	44584.71	1
17	17	2025-05-06 11:31:29.313029	66640.49	1
18	18	2025-05-06 11:31:29.313029	76506.91	1
19	19	2025-05-06 11:31:29.313029	21218.12	1
20	20	2025-05-06 11:31:29.313029	30348.29	1
21	21	2025-05-06 11:31:29.313029	55470.26	1
22	22	2025-05-06 11:31:29.313029	53956.23	1
23	23	2025-05-06 11:31:29.313029	61006.38	1
24	24	2025-05-06 11:31:29.313029	68200.03	1
25	25	2025-05-06 11:31:29.313029	98179.84	1
26	26	2025-05-06 11:31:29.313029	80879.93	1
27	27	2025-05-06 11:31:29.313029	39962.21	1
28	28	2025-05-06 11:31:29.313029	69728.46	1
29	29	2025-05-06 11:31:29.313029	33856.69	1
30	30	2025-05-06 11:31:29.313029	73810.95	1
31	32	2025-05-11 13:20:52.304111	2000.00	1
32	33	2025-05-11 14:28:39.998264	100.00	1
33	34	2025-05-16 11:58:43.589981	77.00	1
34	34	2025-05-16 12:00:34.212234	900.00	1
\.


--
-- Data for Name: bond_payment_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bond_payment_types (id, payment_type) FROM stdin;
\.


--
-- Data for Name: bonds; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bonds (id, maturity_date, coupon_rate, face_value, issue_date, amortization) FROM stdin;
\.


--
-- Data for Name: bonds_payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bonds_payments (id, bond_id, payment_type, payment_date, payment_amount, currency_id) FROM stdin;
\.


--
-- Data for Name: currencies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.currencies (id, code) FROM stdin;
1	USD
2	EUR
3	GBP
4	JPY
5	CHF
6	RUB
\.


--
-- Data for Name: customer_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customer_accounts (id, customer_id, phone_number, email, login, password_hash) FROM stdin;
1	1	+1-555-0101	john.smith@email.com	jsmith1	$2a$10$abc123...
2	2	+1-555-0102	emma.johnson@email.com	ejohnson2	$2a$10$def456...
3	3	+1-555-0103	michael.brown@email.com	mbrown3	$2a$10$ghi789...
4	4	+1-555-0104	sarah.davis@email.com	sdavis4	$2a$10$jkl012...
5	5	+1-555-0105	david.wilson@email.com	dwilson5	$2a$10$mno345...
6	6	+1-555-0106	laura.taylor@email.com	ltaylor6	$2a$10$pqr678...
7	7	+1-555-0107	james.anderson@email.com	janderson7	$2a$10$stu901...
8	8	+1-555-0108	emily.thomas@email.com	ethomas8	$2a$10$vwx234...
9	9	+1-555-0109	robert.jackson@email.com	rjackson9	$2a$10$yza567...
10	10	+1-555-0110	sophia.white@email.com	swhite10	$2a$10$bcd890...
11	11	+1-555-0111	william.harris@email.com	wharris11	$2a$10$efg123...
12	12	+1-555-0112	olivia.lewis@email.com	olewis12	$2a$10$hij456...
13	13	+1-555-0113	thomas.walker@email.com	twalker13	$2a$10$klm789...
14	14	+1-555-0114	isabella.hall@email.com	ihall14	$2a$10$nop012...
15	15	+1-555-0115	charles.allen@email.com	callen15	$2a$10$qrs345...
16	16	+1-555-0116	mia.young@email.com	myoung16	$2a$10$tuv678...
17	17	+1-555-0117	joseph.king@email.com	jking17	$2a$10$wxy901...
18	18	+1-555-0118	ava.wright@email.com	awright18	$2a$10$zab234...
19	19	+1-555-0119	daniel.scott@email.com	dscott19	$2a$10$cde567...
20	20	+1-555-0120	grace.green@email.com	ggreen20	$2a$10$fgh890...
21	21	+1-555-0121	henry.adams@email.com	hadams21	$2a$10$ijk123...
22	22	+1-555-0122	chloe.baker@email.com	cbaker22	$2a$10$lmn456...
23	23	+1-555-0123	samuel.gonzalez@email.com	sgonzalez23	$2a$10$opq789...
24	24	+1-555-0124	lily.nelson@email.com	lnelson24	$2a$10$rst012...
25	25	+1-555-0125	benjamin.carter@email.com	bcarter25	$2a$10$uvw345...
26	26	+1-555-0126	zoe.mitchell@email.com	zmitchell26	$2a$10$xyz678...
27	27	+1-555-0127	ethan.perez@email.com	eperez27	$2a$10$abc901...
28	28	+1-555-0128	hannah.roberts@email.com	hroberts28	$2a$10$def234...
29	29	+1-555-0129	andrew.turner@email.com	aturner29	$2a$10$ghi567...
30	30	+1-555-0130	ella.phillips@email.com	ephillips30	$2a$10$jkl890...
34	34	+78134567890	tserov04@gmail.com	abobusbebrov	be32
35	35	+79271560960	tserov@gmail.com	abobus	be32
\.


--
-- Data for Name: customer_portfolios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customer_portfolios (customer_account_id, security_id, total_quantity, reserved_quantity, avg_buy_price, avg_sell_price, sold_quantity) FROM stdin;
1	29	8	0	565.980000	\N	\N
1	4	9	0	187.430000	\N	\N
1	10	5	0	253.510000	\N	\N
1	6	5	0	599.140000	\N	\N
1	14	5	0	563.640000	\N	\N
2	29	10	0	565.980000	\N	\N
2	4	8	0	187.430000	\N	\N
2	10	5	0	253.510000	\N	\N
2	6	5	0	599.140000	\N	\N
2	14	6	0	563.640000	\N	\N
3	29	9	0	565.980000	\N	\N
3	4	7	0	187.430000	\N	\N
3	10	7	0	253.510000	\N	\N
3	6	6	0	599.140000	\N	\N
3	14	8	0	563.640000	\N	\N
4	29	5	0	565.980000	\N	\N
4	4	5	0	187.430000	\N	\N
4	10	8	0	253.510000	\N	\N
4	6	10	0	599.140000	\N	\N
4	14	10	0	563.640000	\N	\N
5	29	8	0	565.980000	\N	\N
5	4	9	0	187.430000	\N	\N
5	10	10	0	253.510000	\N	\N
5	6	7	0	599.140000	\N	\N
5	14	10	0	563.640000	\N	\N
6	29	10	0	565.980000	\N	\N
6	4	7	0	187.430000	\N	\N
6	10	5	0	253.510000	\N	\N
6	14	10	0	563.640000	\N	\N
6	22	7	0	20.450000	\N	\N
7	4	5	0	187.430000	\N	\N
7	10	9	0	253.510000	\N	\N
7	6	9	0	599.140000	\N	\N
7	14	9	0	563.640000	\N	\N
7	22	8	0	20.450000	\N	\N
8	29	10	0	565.980000	\N	\N
8	4	10	0	187.430000	\N	\N
8	10	6	0	253.510000	\N	\N
8	6	9	0	599.140000	\N	\N
8	14	6	0	563.640000	\N	\N
9	29	7	0	565.980000	\N	\N
9	4	9	0	187.430000	\N	\N
9	10	6	0	253.510000	\N	\N
9	6	9	0	599.140000	\N	\N
9	14	9	0	563.640000	\N	\N
10	29	5	0	565.980000	\N	\N
10	4	6	0	187.430000	\N	\N
10	10	9	0	253.510000	\N	\N
10	6	6	0	599.140000	\N	\N
10	14	7	0	563.640000	\N	\N
11	29	7	0	565.980000	\N	\N
11	4	6	0	187.430000	\N	\N
11	10	8	0	253.510000	\N	\N
11	6	6	0	599.140000	\N	\N
11	14	8	0	563.640000	\N	\N
12	29	5	0	565.980000	\N	\N
12	4	10	0	187.430000	\N	\N
12	10	7	0	253.510000	\N	\N
12	6	5	0	599.140000	\N	\N
12	14	6	0	563.640000	\N	\N
13	29	8	0	565.980000	\N	\N
13	10	9	0	253.510000	\N	\N
13	6	6	0	599.140000	\N	\N
13	14	6	0	563.640000	\N	\N
13	22	8	0	20.450000	\N	\N
14	29	10	0	565.980000	\N	\N
14	4	10	0	187.430000	\N	\N
14	10	9	0	253.510000	\N	\N
14	6	6	0	599.140000	\N	\N
14	14	8	0	563.640000	\N	\N
15	29	10	0	565.980000	\N	\N
15	4	9	0	187.430000	\N	\N
15	10	7	0	253.510000	\N	\N
15	6	7	0	599.140000	\N	\N
15	14	6	0	563.640000	\N	\N
16	29	10	0	565.980000	\N	\N
16	4	8	0	187.430000	\N	\N
16	10	7	0	253.510000	\N	\N
16	6	7	0	599.140000	\N	\N
16	14	10	0	563.640000	\N	\N
17	29	8	0	565.980000	\N	\N
17	4	8	0	187.430000	\N	\N
17	10	6	0	253.510000	\N	\N
17	6	7	0	599.140000	\N	\N
17	14	5	0	563.640000	\N	\N
18	29	7	0	565.980000	\N	\N
18	4	9	0	187.430000	\N	\N
18	10	7	0	253.510000	\N	\N
18	6	7	0	599.140000	\N	\N
18	14	5	0	563.640000	\N	\N
19	4	5	0	187.430000	\N	\N
19	10	10	0	253.510000	\N	\N
19	6	6	0	599.140000	\N	\N
19	22	7	0	20.450000	\N	\N
19	13	6	0	350.540000	\N	\N
20	29	8	0	565.980000	\N	\N
20	4	5	0	187.430000	\N	\N
20	10	8	0	253.510000	\N	\N
20	6	8	0	599.140000	\N	\N
20	14	5	0	563.640000	\N	\N
21	29	6	0	565.980000	\N	\N
21	4	9	0	187.430000	\N	\N
21	10	6	0	253.510000	\N	\N
21	6	7	0	599.140000	\N	\N
21	14	5	0	563.640000	\N	\N
22	29	6	0	565.980000	\N	\N
22	4	5	0	187.430000	\N	\N
22	10	6	0	253.510000	\N	\N
22	6	10	0	599.140000	\N	\N
22	14	7	0	563.640000	\N	\N
23	29	6	0	565.980000	\N	\N
23	4	7	0	187.430000	\N	\N
23	10	7	0	253.510000	\N	\N
23	6	6	0	599.140000	\N	\N
23	14	5	0	563.640000	\N	\N
24	29	7	0	565.980000	\N	\N
24	4	9	0	187.430000	\N	\N
24	10	5	0	253.510000	\N	\N
24	6	5	0	599.140000	\N	\N
24	14	9	0	563.640000	\N	\N
25	29	8	0	565.980000	\N	\N
25	4	7	0	187.430000	\N	\N
25	10	10	0	253.510000	\N	\N
25	6	9	0	599.140000	\N	\N
25	14	10	0	563.640000	\N	\N
26	29	8	0	565.980000	\N	\N
26	4	7	0	187.430000	\N	\N
26	10	6	0	253.510000	\N	\N
26	6	5	0	599.140000	\N	\N
26	14	8	0	563.640000	\N	\N
27	29	9	0	565.980000	\N	\N
27	4	7	0	187.430000	\N	\N
27	10	8	0	253.510000	\N	\N
27	6	7	0	599.140000	\N	\N
27	14	10	0	563.640000	\N	\N
28	29	5	0	565.980000	\N	\N
28	4	7	0	187.430000	\N	\N
28	10	6	0	253.510000	\N	\N
28	6	10	0	599.140000	\N	\N
28	14	7	0	563.640000	\N	\N
29	29	9	0	565.980000	\N	\N
29	4	10	0	187.430000	\N	\N
29	10	9	0	253.510000	\N	\N
29	6	5	0	599.140000	\N	\N
29	14	5	0	563.640000	\N	\N
30	4	5	0	187.430000	\N	\N
30	10	6	0	253.510000	\N	\N
30	6	8	0	599.140000	\N	\N
30	14	10	0	563.640000	\N	\N
30	22	6	0	20.450000	\N	\N
34	21	1	0	384.710680	\N	\N
35	28	1	0	43.750860	\N	\N
35	1	1	0	201.994170	\N	\N
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (id, first_name, last_name, date_of_birth, passport_series, address, tax_id) FROM stdin;
1	John	Smith	1985-03-15	AB1234567	123 Main St, Springfield	TAX001
2	Emma	Johnson	1990-07-22	CD9876543	\N	TAX002
3	Michael	Brown	1978-11-30	EF4567891	456 Oak Ave, Metropolis	TAX003
4	Sarah	Davis	1995-01-10	GH2345678	789 Pine Rd, Gotham	TAX004
5	David	Wilson	1982-06-05	IJ8901234	\N	TAX005
6	Laura	Taylor	1988-09-18	KL5678901	321 Elm St, Star City	TAX006
7	James	Anderson	1975-12-25	MN1234567	654 Cedar Ln, Central City	TAX007
8	Emily	Thomas	1993-04-12	OP7890123	\N	TAX008
9	Robert	Jackson	1980-08-08	QR3456789	987 Birch Dr, Coast City	TAX009
10	Sophia	White	1997-02-28	ST9012345	147 Maple Ave, Bludhaven	TAX010
11	William	Harris	1983-05-20	UV5678901	\N	TAX011
12	Olivia	Lewis	1991-10-15	WX1234567	258 Willow St, Keystone	TAX012
13	Thomas	Walker	1977-07-07	YZ7890123	369 Spruce Rd, Smallville	TAX013
14	Isabella	Hall	1994-03-03	AB2345678	\N	TAX014
15	Charles	Allen	1986-11-11	CD8901234	741 Oak St, Midway City	TAX015
16	Mia	Young	1989-06-30	EF4567890	852 Pine Ave, Fawcett City	TAX016
17	Joseph	King	1981-01-25	GH0123456	\N	TAX017
18	Ava	Wright	1996-08-14	IJ6789012	963 Cedar Dr, Hub City	TAX018
19	Daniel	Scott	1979-04-09	KL2345678	159 Elm Ln, Opal City	TAX019
20	Grace	Green	1992-12-02	MN8901234	\N	TAX020
21	Henry	Adams	1984-09-27	OP4567890	357 Birch St, Ivy Town	TAX021
22	Chloe	Baker	1998-05-16	QR0123456	468 Maple Rd, Happy Harbor	TAX022
23	Samuel	Gonzalez	1976-02-19	ST6789012	\N	TAX023
24	Lily	Nelson	1990-10-31	UV2345678	579 Willow Ave, Gateway City	TAX024
25	Benjamin	Carter	1987-07-04	WX8901234	680 Spruce St, Capital City	TAX025
26	Zoe	Mitchell	1993-03-21	YZ4567890	\N	TAX026
27	Ethan	Perez	1980-11-13	AB0123456	791 Oak Dr, Harmony	TAX027
28	Hannah	Roberts	1995-06-06	CD6789012	802 Pine Ln, Civic City	TAX028
29	Andrew	Turner	1978-01-29	EF2345678	\N	TAX029
30	Ella	Phillips	1991-09-23	GH8901234	913 Cedar Ave, Zenith	TAX030
34	abobus	bebrov	2005-10-30	1234 567890	abc	1234654376754
35	тимофей	серов	2005-10-03	1234 563654	ulitsa pushkina	325464645
\.


--
-- Data for Name: order_status; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_status (id, status) FROM stdin;
1	OPEN
2	EXECUTED
4	CANCELED
3	PARTIALLY EXECUTED
\.


--
-- Data for Name: order_type; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_type (id, type) FROM stdin;
1	BUY
2	SELL
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (id, customer_account_id, security_id, savings_account_id, price, fee, quantity, available_quantity, created_at, order_type_id, order_status_id) FROM stdin;
2	2	1	2	203.89	1.22334	2	2	2025-05-06 12:11:08.486781	2	1
3	3	1	3	206.39	1.85751	3	3	2025-05-06 12:11:08.486781	2	1
4	4	1	4	208.89	0.62667	1	1	2025-05-06 12:11:08.486781	2	1
5	5	1	5	211.39	0.63417	1	1	2025-05-06 12:11:08.486781	2	1
6	6	1	6	213.89	1.92501	3	3	2025-05-06 12:11:08.486781	2	1
7	7	1	7	216.39	1.29834	2	2	2025-05-06 12:11:08.486781	2	1
8	8	1	8	218.89	1.97001	3	3	2025-05-06 12:11:08.486781	2	1
9	9	1	9	221.39	0.66417	1	1	2025-05-06 12:11:08.486781	2	1
10	10	1	10	223.89	1.34334	2	2	2025-05-06 12:11:08.486781	2	1
11	11	1	11	196.39	0.58917	1	1	2025-05-06 12:11:08.486781	1	1
12	12	1	12	193.89	1.16334	2	2	2025-05-06 12:11:08.486781	1	1
13	13	1	13	191.39	1.72251	3	3	2025-05-06 12:11:08.486781	1	1
14	14	1	14	188.89	0.56667	1	1	2025-05-06 12:11:08.486781	1	1
15	15	1	15	186.39	1.67751	3	3	2025-05-06 12:11:08.486781	1	1
16	16	1	16	183.89	1.65501	3	3	2025-05-06 12:11:08.486781	1	1
17	17	1	17	181.39	0.54417	1	1	2025-05-06 12:11:08.486781	1	1
18	18	1	18	178.89	1.61001	3	3	2025-05-06 12:11:08.486781	1	1
19	19	1	19	176.39	0.52917	1	1	2025-05-06 12:11:08.486781	1	1
20	20	1	20	173.89	1.04334	2	2	2025-05-06 12:11:08.486781	1	1
21	1	2	1	438.67	1.31601	1	1	2025-05-06 12:11:08.486781	2	1
22	2	2	2	441.17	2.64702	2	2	2025-05-06 12:11:08.486781	2	1
23	3	2	3	443.67	2.66202	2	2	2025-05-06 12:11:08.486781	2	1
24	4	2	4	446.17	4.01553	3	3	2025-05-06 12:11:08.486781	2	1
25	5	2	5	448.67	1.34601	1	1	2025-05-06 12:11:08.486781	2	1
26	6	2	6	451.17	1.35351	1	1	2025-05-06 12:11:08.486781	2	1
27	7	2	7	453.67	4.08303	3	3	2025-05-06 12:11:08.486781	2	1
28	8	2	8	456.17	4.10553	3	3	2025-05-06 12:11:08.486781	2	1
29	9	2	9	458.67	2.75202	2	2	2025-05-06 12:11:08.486781	2	1
30	10	2	10	461.17	1.38351	1	1	2025-05-06 12:11:08.486781	2	1
31	11	2	11	433.67	2.60202	2	2	2025-05-06 12:11:08.486781	1	1
32	12	2	12	431.17	3.88053	3	3	2025-05-06 12:11:08.486781	1	1
33	13	2	13	428.67	3.85803	3	3	2025-05-06 12:11:08.486781	1	1
34	14	2	14	426.17	2.55702	2	2	2025-05-06 12:11:08.486781	1	1
35	15	2	15	423.67	2.54202	2	2	2025-05-06 12:11:08.486781	1	1
36	16	2	16	421.17	3.79053	3	3	2025-05-06 12:11:08.486781	1	1
37	17	2	17	418.67	1.25601	1	1	2025-05-06 12:11:08.486781	1	1
38	18	2	18	416.17	1.24851	1	1	2025-05-06 12:11:08.486781	1	1
39	19	2	19	413.67	1.24101	1	1	2025-05-06 12:11:08.486781	1	1
40	20	2	20	411.17	2.46702	2	2	2025-05-06 12:11:08.486781	1	1
41	1	3	1	116.32	0.34896	1	1	2025-05-06 12:11:08.486781	2	1
42	2	3	2	118.82	1.06938	3	3	2025-05-06 12:11:08.486781	2	1
43	3	3	3	121.32	1.09188	3	3	2025-05-06 12:11:08.486781	2	1
44	4	3	4	123.82	0.74292	2	2	2025-05-06 12:11:08.486781	2	1
45	5	3	5	126.32	0.37896	1	1	2025-05-06 12:11:08.486781	2	1
46	6	3	6	128.82	0.38646	1	1	2025-05-06 12:11:08.486781	2	1
47	7	3	7	131.32	0.78792	2	2	2025-05-06 12:11:08.486781	2	1
48	8	3	8	133.82	0.40146	1	1	2025-05-06 12:11:08.486781	2	1
49	9	3	9	136.32	1.22688	3	3	2025-05-06 12:11:08.486781	2	1
50	10	3	10	138.82	0.41646	1	1	2025-05-06 12:11:08.486781	2	1
51	11	3	11	111.32	1.00188	3	3	2025-05-06 12:11:08.486781	1	1
52	12	3	12	108.82	0.97938	3	3	2025-05-06 12:11:08.486781	1	1
53	13	3	13	106.32	0.95688	3	3	2025-05-06 12:11:08.486781	1	1
54	14	3	14	103.82	0.31146	1	1	2025-05-06 12:11:08.486781	1	1
55	15	3	15	101.32	0.60792	2	2	2025-05-06 12:11:08.486781	1	1
56	16	3	16	98.82	0.29646	1	1	2025-05-06 12:11:08.486781	1	1
57	17	3	17	96.32	0.28896	1	1	2025-05-06 12:11:08.486781	1	1
58	18	3	18	93.82	0.28146	1	1	2025-05-06 12:11:08.486781	1	1
59	19	3	19	91.32	0.82188	3	3	2025-05-06 12:11:08.486781	1	1
60	20	3	20	88.82	0.26646	1	1	2025-05-06 12:11:08.486781	1	1
61	1	4	1	188.85	0.56655	1	1	2025-05-06 12:11:08.486781	2	1
62	2	4	2	191.35	0.57405	1	1	2025-05-06 12:11:08.486781	2	1
63	3	4	3	193.85	1.74465	3	3	2025-05-06 12:11:08.486781	2	1
64	4	4	4	196.35	0.58905	1	1	2025-05-06 12:11:08.486781	2	1
65	5	4	5	198.85	1.78965	3	3	2025-05-06 12:11:08.486781	2	1
66	6	4	6	201.35	1.81215	3	3	2025-05-06 12:11:08.486781	2	1
67	7	4	7	203.85	1.22310	2	2	2025-05-06 12:11:08.486781	2	1
68	8	4	8	206.35	1.85715	3	3	2025-05-06 12:11:08.486781	2	1
69	9	4	9	208.85	0.62655	1	1	2025-05-06 12:11:08.486781	2	1
70	10	4	10	211.35	1.90215	3	3	2025-05-06 12:11:08.486781	2	1
71	11	4	11	183.85	1.65465	3	3	2025-05-06 12:11:08.486781	1	1
72	12	4	12	181.35	0.54405	1	1	2025-05-06 12:11:08.486781	1	1
73	13	4	13	178.85	1.60965	3	3	2025-05-06 12:11:08.486781	1	1
74	14	4	14	176.35	0.52905	1	1	2025-05-06 12:11:08.486781	1	1
75	15	4	15	173.85	0.52155	1	1	2025-05-06 12:11:08.486781	1	1
76	16	4	16	171.35	1.02810	2	2	2025-05-06 12:11:08.486781	1	1
77	17	4	17	168.85	0.50655	1	1	2025-05-06 12:11:08.486781	1	1
78	18	4	18	166.35	0.99810	2	2	2025-05-06 12:11:08.486781	1	1
79	19	4	19	163.85	0.49155	1	1	2025-05-06 12:11:08.486781	1	1
80	20	4	20	161.35	0.48405	1	1	2025-05-06 12:11:08.486781	1	1
81	1	5	1	166.71	0.50013	1	1	2025-05-06 12:11:08.486781	2	1
82	2	5	2	169.21	1.01526	2	2	2025-05-06 12:11:08.486781	2	1
83	3	5	3	171.71	0.51513	1	1	2025-05-06 12:11:08.486781	2	1
84	4	5	4	174.21	0.52263	1	1	2025-05-06 12:11:08.486781	2	1
85	5	5	5	176.71	0.53013	1	1	2025-05-06 12:11:08.486781	2	1
86	6	5	6	179.21	1.07526	2	2	2025-05-06 12:11:08.486781	2	1
87	7	5	7	181.71	0.54513	1	1	2025-05-06 12:11:08.486781	2	1
88	8	5	8	184.21	0.55263	1	1	2025-05-06 12:11:08.486781	2	1
89	9	5	9	186.71	1.12026	2	2	2025-05-06 12:11:08.486781	2	1
90	10	5	10	189.21	1.70289	3	3	2025-05-06 12:11:08.486781	2	1
91	11	5	11	161.71	0.48513	1	1	2025-05-06 12:11:08.486781	1	1
92	12	5	12	159.21	0.95526	2	2	2025-05-06 12:11:08.486781	1	1
93	13	5	13	156.71	0.94026	2	2	2025-05-06 12:11:08.486781	1	1
94	14	5	14	154.21	0.92526	2	2	2025-05-06 12:11:08.486781	1	1
95	15	5	15	151.71	0.45513	1	1	2025-05-06 12:11:08.486781	1	1
96	16	5	16	149.21	0.44763	1	1	2025-05-06 12:11:08.486781	1	1
97	17	5	17	146.71	0.44013	1	1	2025-05-06 12:11:08.486781	1	1
98	18	5	18	144.21	0.43263	1	1	2025-05-06 12:11:08.486781	1	1
99	19	5	19	141.71	0.42513	1	1	2025-05-06 12:11:08.486781	1	1
100	20	5	20	139.21	1.25289	3	3	2025-05-06 12:11:08.486781	1	1
101	1	6	1	601.77	3.61062	2	2	2025-05-06 12:11:08.486781	2	1
102	2	6	2	604.27	5.43843	3	3	2025-05-06 12:11:08.486781	2	1
103	3	6	3	606.77	5.46093	3	3	2025-05-06 12:11:08.486781	2	1
104	4	6	4	609.27	1.82781	1	1	2025-05-06 12:11:08.486781	2	1
105	5	6	5	611.77	3.67062	2	2	2025-05-06 12:11:08.486781	2	1
106	6	6	6	614.27	3.68562	2	2	2025-05-06 12:11:08.486781	2	1
107	7	6	7	616.77	1.85031	1	1	2025-05-06 12:11:08.486781	2	1
108	8	6	8	619.27	5.57343	3	3	2025-05-06 12:11:08.486781	2	1
109	9	6	9	621.77	3.73062	2	2	2025-05-06 12:11:08.486781	2	1
110	10	6	10	624.27	1.87281	1	1	2025-05-06 12:11:08.486781	2	1
111	11	6	11	596.77	3.58062	2	2	2025-05-06 12:11:08.486781	1	1
112	12	6	12	594.27	3.56562	2	2	2025-05-06 12:11:08.486781	1	1
113	13	6	13	591.77	5.32593	3	3	2025-05-06 12:11:08.486781	1	1
114	14	6	14	589.27	1.76781	1	1	2025-05-06 12:11:08.486781	1	1
115	15	6	15	586.77	1.76031	1	1	2025-05-06 12:11:08.486781	1	1
116	16	6	16	584.27	3.50562	2	2	2025-05-06 12:11:08.486781	1	1
117	17	6	17	581.77	5.23593	3	3	2025-05-06 12:11:08.486781	1	1
118	18	6	18	579.27	5.21343	3	3	2025-05-06 12:11:08.486781	1	1
119	19	6	19	576.77	1.73031	1	1	2025-05-06 12:11:08.486781	1	1
120	20	6	20	574.27	5.16843	3	3	2025-05-06 12:11:08.486781	1	1
121	1	7	1	282.76	1.69656	2	2	2025-05-06 12:11:08.486781	2	1
122	2	7	2	285.26	0.85578	1	1	2025-05-06 12:11:08.486781	2	1
123	3	7	3	287.76	2.58984	3	3	2025-05-06 12:11:08.486781	2	1
124	4	7	4	290.26	2.61234	3	3	2025-05-06 12:11:08.486781	2	1
125	5	7	5	292.76	2.63484	3	3	2025-05-06 12:11:08.486781	2	1
126	6	7	6	295.26	1.77156	2	2	2025-05-06 12:11:08.486781	2	1
127	7	7	7	297.76	2.67984	3	3	2025-05-06 12:11:08.486781	2	1
128	8	7	8	300.26	0.90078	1	1	2025-05-06 12:11:08.486781	2	1
129	9	7	9	302.76	0.90828	1	1	2025-05-06 12:11:08.486781	2	1
130	10	7	10	305.26	0.91578	1	1	2025-05-06 12:11:08.486781	2	1
131	11	7	11	277.76	2.49984	3	3	2025-05-06 12:11:08.486781	1	1
132	12	7	12	275.26	1.65156	2	2	2025-05-06 12:11:08.486781	1	1
133	13	7	13	272.76	1.63656	2	2	2025-05-06 12:11:08.486781	1	1
134	14	7	14	270.26	0.81078	1	1	2025-05-06 12:11:08.486781	1	1
135	15	7	15	267.76	1.60656	2	2	2025-05-06 12:11:08.486781	1	1
136	16	7	16	265.26	0.79578	1	1	2025-05-06 12:11:08.486781	1	1
137	17	7	17	262.76	0.78828	1	1	2025-05-06 12:11:08.486781	1	1
138	18	7	18	260.26	2.34234	3	3	2025-05-06 12:11:08.486781	1	1
139	19	7	19	257.76	2.31984	3	3	2025-05-06 12:11:08.486781	1	1
140	20	7	20	255.26	1.53156	2	2	2025-05-06 12:11:08.486781	1	1
141	1	8	1	769962.50	6929.66250	3	3	2025-05-06 12:11:08.486781	2	1
142	2	8	2	769965.00	6929.68500	3	3	2025-05-06 12:11:08.486781	2	1
143	3	8	3	769967.50	6929.70750	3	3	2025-05-06 12:11:08.486781	2	1
144	4	8	4	769970.00	4619.82000	2	2	2025-05-06 12:11:08.486781	2	1
145	5	8	5	769972.50	2309.91750	1	1	2025-05-06 12:11:08.486781	2	1
146	6	8	6	769975.00	4619.85000	2	2	2025-05-06 12:11:08.486781	2	1
147	7	8	7	769977.50	6929.79750	3	3	2025-05-06 12:11:08.486781	2	1
148	8	8	8	769980.00	4619.88000	2	2	2025-05-06 12:11:08.486781	2	1
149	9	8	9	769982.50	4619.89500	2	2	2025-05-06 12:11:08.486781	2	1
150	10	8	10	769985.00	2309.95500	1	1	2025-05-06 12:11:08.486781	2	1
151	11	8	11	769957.50	6929.61750	3	3	2025-05-06 12:11:08.486781	1	1
152	12	8	12	769955.00	4619.73000	2	2	2025-05-06 12:11:08.486781	1	1
153	13	8	13	769952.50	4619.71500	2	2	2025-05-06 12:11:08.486781	1	1
154	14	8	14	769950.00	2309.85000	1	1	2025-05-06 12:11:08.486781	1	1
155	15	8	15	769947.50	6929.52750	3	3	2025-05-06 12:11:08.486781	1	1
156	16	8	16	769945.00	4619.67000	2	2	2025-05-06 12:11:08.486781	1	1
157	17	8	17	769942.50	6929.48250	3	3	2025-05-06 12:11:08.486781	1	1
158	18	8	18	769940.00	2309.82000	1	1	2025-05-06 12:11:08.486781	1	1
159	19	8	19	769937.50	4619.62500	2	2	2025-05-06 12:11:08.486781	1	1
160	20	8	20	769935.00	2309.80500	1	1	2025-05-06 12:11:08.486781	1	1
161	1	9	1	823.96	2.47188	1	1	2025-05-06 12:11:08.486781	2	1
162	2	9	2	826.46	4.95876	2	2	2025-05-06 12:11:08.486781	2	1
163	3	9	3	828.96	2.48688	1	1	2025-05-06 12:11:08.486781	2	1
164	4	9	4	831.46	4.98876	2	2	2025-05-06 12:11:08.486781	2	1
165	5	9	5	833.96	5.00376	2	2	2025-05-06 12:11:08.486781	2	1
166	6	9	6	836.46	2.50938	1	1	2025-05-06 12:11:08.486781	2	1
167	7	9	7	838.96	2.51688	1	1	2025-05-06 12:11:08.486781	2	1
168	8	9	8	841.46	2.52438	1	1	2025-05-06 12:11:08.486781	2	1
169	9	9	9	843.96	7.59564	3	3	2025-05-06 12:11:08.486781	2	1
170	10	9	10	846.46	2.53938	1	1	2025-05-06 12:11:08.486781	2	1
171	11	9	11	818.96	7.37064	3	3	2025-05-06 12:11:08.486781	1	1
172	12	9	12	816.46	7.34814	3	3	2025-05-06 12:11:08.486781	1	1
173	13	9	13	813.96	2.44188	1	1	2025-05-06 12:11:08.486781	1	1
174	14	9	14	811.46	7.30314	3	3	2025-05-06 12:11:08.486781	1	1
175	15	9	15	808.96	4.85376	2	2	2025-05-06 12:11:08.486781	1	1
176	16	9	16	806.46	2.41938	1	1	2025-05-06 12:11:08.486781	1	1
177	17	9	17	803.96	4.82376	2	2	2025-05-06 12:11:08.486781	1	1
178	18	9	18	801.46	2.40438	1	1	2025-05-06 12:11:08.486781	1	1
179	19	9	19	798.96	4.79376	2	2	2025-05-06 12:11:08.486781	1	1
180	20	9	20	796.46	7.16814	3	3	2025-05-06 12:11:08.486781	1	1
181	1	10	1	255.06	1.53036	2	2	2025-05-06 12:11:08.486781	2	1
182	2	10	2	257.56	2.31804	3	3	2025-05-06 12:11:08.486781	2	1
183	3	10	3	260.06	2.34054	3	3	2025-05-06 12:11:08.486781	2	1
184	4	10	4	262.56	1.57536	2	2	2025-05-06 12:11:08.486781	2	1
185	5	10	5	265.06	0.79518	1	1	2025-05-06 12:11:08.486781	2	1
186	6	10	6	267.56	2.40804	3	3	2025-05-06 12:11:08.486781	2	1
187	7	10	7	270.06	0.81018	1	1	2025-05-06 12:11:08.486781	2	1
188	8	10	8	272.56	1.63536	2	2	2025-05-06 12:11:08.486781	2	1
189	9	10	9	275.06	1.65036	2	2	2025-05-06 12:11:08.486781	2	1
190	10	10	10	277.56	1.66536	2	2	2025-05-06 12:11:08.486781	2	1
191	11	10	11	250.06	0.75018	1	1	2025-05-06 12:11:08.486781	1	1
192	12	10	12	247.56	1.48536	2	2	2025-05-06 12:11:08.486781	1	1
193	13	10	13	245.06	2.20554	3	3	2025-05-06 12:11:08.486781	1	1
194	14	10	14	242.56	0.72768	1	1	2025-05-06 12:11:08.486781	1	1
195	15	10	15	240.06	0.72018	1	1	2025-05-06 12:11:08.486781	1	1
196	16	10	16	237.56	1.42536	2	2	2025-05-06 12:11:08.486781	1	1
197	17	10	17	235.06	2.11554	3	3	2025-05-06 12:11:08.486781	1	1
198	18	10	18	232.56	1.39536	2	2	2025-05-06 12:11:08.486781	1	1
199	19	10	19	230.06	1.38036	2	2	2025-05-06 12:11:08.486781	1	1
200	20	10	20	227.56	2.04804	3	3	2025-05-06 12:11:08.486781	1	1
201	1	11	1	101.83	0.30549	1	1	2025-05-06 12:11:08.486781	2	1
202	2	11	2	104.33	0.31299	1	1	2025-05-06 12:11:08.486781	2	1
203	3	11	3	106.83	0.32049	1	1	2025-05-06 12:11:08.486781	2	1
204	4	11	4	109.33	0.98397	3	3	2025-05-06 12:11:08.486781	2	1
205	5	11	5	111.83	1.00647	3	3	2025-05-06 12:11:08.486781	2	1
206	6	11	6	114.33	0.68598	2	2	2025-05-06 12:11:08.486781	2	1
207	7	11	7	116.83	0.70098	2	2	2025-05-06 12:11:08.486781	2	1
208	8	11	8	119.33	1.07397	3	3	2025-05-06 12:11:08.486781	2	1
209	9	11	9	121.83	1.09647	3	3	2025-05-06 12:11:08.486781	2	1
210	10	11	10	124.33	0.74598	2	2	2025-05-06 12:11:08.486781	2	1
211	11	11	11	96.83	0.58098	2	2	2025-05-06 12:11:08.486781	1	1
212	12	11	12	94.33	0.84897	3	3	2025-05-06 12:11:08.486781	1	1
213	13	11	13	91.83	0.27549	1	1	2025-05-06 12:11:08.486781	1	1
214	14	11	14	89.33	0.26799	1	1	2025-05-06 12:11:08.486781	1	1
215	15	11	15	86.83	0.26049	1	1	2025-05-06 12:11:08.486781	1	1
216	16	11	16	84.33	0.75897	3	3	2025-05-06 12:11:08.486781	1	1
217	17	11	17	81.83	0.49098	2	2	2025-05-06 12:11:08.486781	1	1
218	18	11	18	79.33	0.23799	1	1	2025-05-06 12:11:08.486781	1	1
219	19	11	19	76.83	0.69147	3	3	2025-05-06 12:11:08.486781	1	1
220	20	11	20	74.33	0.44598	2	2	2025-05-06 12:11:08.486781	1	1
221	1	12	1	407.31	2.44386	2	2	2025-05-06 12:11:08.486781	2	1
222	2	12	2	409.81	1.22943	1	1	2025-05-06 12:11:08.486781	2	1
223	3	12	3	412.31	2.47386	2	2	2025-05-06 12:11:08.486781	2	1
224	4	12	4	414.81	2.48886	2	2	2025-05-06 12:11:08.486781	2	1
225	5	12	5	417.31	1.25193	1	1	2025-05-06 12:11:08.486781	2	1
226	6	12	6	419.81	2.51886	2	2	2025-05-06 12:11:08.486781	2	1
227	7	12	7	422.31	2.53386	2	2	2025-05-06 12:11:08.486781	2	1
228	8	12	8	424.81	1.27443	1	1	2025-05-06 12:11:08.486781	2	1
229	9	12	9	427.31	2.56386	2	2	2025-05-06 12:11:08.486781	2	1
230	10	12	10	429.81	1.28943	1	1	2025-05-06 12:11:08.486781	2	1
231	11	12	11	402.31	1.20693	1	1	2025-05-06 12:11:08.486781	1	1
232	12	12	12	399.81	3.59829	3	3	2025-05-06 12:11:08.486781	1	1
233	13	12	13	397.31	2.38386	2	2	2025-05-06 12:11:08.486781	1	1
234	14	12	14	394.81	3.55329	3	3	2025-05-06 12:11:08.486781	1	1
235	15	12	15	392.31	1.17693	1	1	2025-05-06 12:11:08.486781	1	1
236	16	12	16	389.81	2.33886	2	2	2025-05-06 12:11:08.486781	1	1
237	17	12	17	387.31	3.48579	3	3	2025-05-06 12:11:08.486781	1	1
238	18	12	18	384.81	1.15443	1	1	2025-05-06 12:11:08.486781	1	1
239	19	12	19	382.31	3.44079	3	3	2025-05-06 12:11:08.486781	1	1
240	20	12	20	379.81	1.13943	1	1	2025-05-06 12:11:08.486781	1	1
241	1	13	1	351.14	3.16026	3	3	2025-05-06 12:11:08.486781	2	1
242	2	13	2	353.64	2.12184	2	2	2025-05-06 12:11:08.486781	2	1
243	3	13	3	356.14	3.20526	3	3	2025-05-06 12:11:08.486781	2	1
244	4	13	4	358.64	1.07592	1	1	2025-05-06 12:11:08.486781	2	1
245	5	13	5	361.14	1.08342	1	1	2025-05-06 12:11:08.486781	2	1
246	6	13	6	363.64	2.18184	2	2	2025-05-06 12:11:08.486781	2	1
247	7	13	7	366.14	1.09842	1	1	2025-05-06 12:11:08.486781	2	1
248	8	13	8	368.64	2.21184	2	2	2025-05-06 12:11:08.486781	2	1
249	9	13	9	371.14	1.11342	1	1	2025-05-06 12:11:08.486781	2	1
250	10	13	10	373.64	1.12092	1	1	2025-05-06 12:11:08.486781	2	1
251	11	13	11	346.14	3.11526	3	3	2025-05-06 12:11:08.486781	1	1
252	12	13	12	343.64	3.09276	3	3	2025-05-06 12:11:08.486781	1	1
253	13	13	13	341.14	3.07026	3	3	2025-05-06 12:11:08.486781	1	1
254	14	13	14	338.64	1.01592	1	1	2025-05-06 12:11:08.486781	1	1
255	15	13	15	336.14	3.02526	3	3	2025-05-06 12:11:08.486781	1	1
256	16	13	16	333.64	3.00276	3	3	2025-05-06 12:11:08.486781	1	1
257	17	13	17	331.14	1.98684	2	2	2025-05-06 12:11:08.486781	1	1
258	18	13	18	328.64	1.97184	2	2	2025-05-06 12:11:08.486781	1	1
259	19	13	19	326.14	1.95684	2	2	2025-05-06 12:11:08.486781	1	1
260	20	13	20	323.64	1.94184	2	2	2025-05-06 12:11:08.486781	1	1
261	1	14	1	563.62	3.38172	2	2	2025-05-06 12:11:08.486781	2	1
262	2	14	2	566.12	3.39672	2	2	2025-05-06 12:11:08.486781	2	1
263	3	14	3	568.62	5.11758	3	3	2025-05-06 12:11:08.486781	2	1
264	4	14	4	571.12	3.42672	2	2	2025-05-06 12:11:08.486781	2	1
265	5	14	5	573.62	1.72086	1	1	2025-05-06 12:11:08.486781	2	1
266	6	14	6	576.12	3.45672	2	2	2025-05-06 12:11:08.486781	2	1
267	7	14	7	578.62	1.73586	1	1	2025-05-06 12:11:08.486781	2	1
268	8	14	8	581.12	1.74336	1	1	2025-05-06 12:11:08.486781	2	1
269	9	14	9	583.62	5.25258	3	3	2025-05-06 12:11:08.486781	2	1
270	10	14	10	586.12	5.27508	3	3	2025-05-06 12:11:08.486781	2	1
271	11	14	11	558.62	5.02758	3	3	2025-05-06 12:11:08.486781	1	1
272	12	14	12	556.12	3.33672	2	2	2025-05-06 12:11:08.486781	1	1
273	13	14	13	553.62	4.98258	3	3	2025-05-06 12:11:08.486781	1	1
274	14	14	14	551.12	4.96008	3	3	2025-05-06 12:11:08.486781	1	1
275	15	14	15	548.62	4.93758	3	3	2025-05-06 12:11:08.486781	1	1
276	16	14	16	546.12	3.27672	2	2	2025-05-06 12:11:08.486781	1	1
277	17	14	17	543.62	4.89258	3	3	2025-05-06 12:11:08.486781	1	1
278	18	14	18	541.12	3.24672	2	2	2025-05-06 12:11:08.486781	1	1
279	19	14	19	538.62	4.84758	3	3	2025-05-06 12:11:08.486781	1	1
280	20	14	20	536.12	4.82508	3	3	2025-05-06 12:11:08.486781	1	1
281	1	15	1	364.23	2.18538	2	2	2025-05-06 12:11:08.486781	2	1
282	2	15	2	366.73	3.30057	3	3	2025-05-06 12:11:08.486781	2	1
283	3	15	3	369.23	3.32307	3	3	2025-05-06 12:11:08.486781	2	1
284	4	15	4	371.73	2.23038	2	2	2025-05-06 12:11:08.486781	2	1
285	5	15	5	374.23	2.24538	2	2	2025-05-06 12:11:08.486781	2	1
286	6	15	6	376.73	3.39057	3	3	2025-05-06 12:11:08.486781	2	1
287	7	15	7	379.23	1.13769	1	1	2025-05-06 12:11:08.486781	2	1
288	8	15	8	381.73	3.43557	3	3	2025-05-06 12:11:08.486781	2	1
289	9	15	9	384.23	2.30538	2	2	2025-05-06 12:11:08.486781	2	1
290	10	15	10	386.73	3.48057	3	3	2025-05-06 12:11:08.486781	2	1
291	11	15	11	359.23	1.07769	1	1	2025-05-06 12:11:08.486781	1	1
292	12	15	12	356.73	1.07019	1	1	2025-05-06 12:11:08.486781	1	1
293	13	15	13	354.23	3.18807	3	3	2025-05-06 12:11:08.486781	1	1
294	14	15	14	351.73	3.16557	3	3	2025-05-06 12:11:08.486781	1	1
295	15	15	15	349.23	2.09538	2	2	2025-05-06 12:11:08.486781	1	1
296	16	15	16	346.73	1.04019	1	1	2025-05-06 12:11:08.486781	1	1
297	17	15	17	344.23	2.06538	2	2	2025-05-06 12:11:08.486781	1	1
298	18	15	18	341.73	1.02519	1	1	2025-05-06 12:11:08.486781	1	1
299	19	15	19	339.23	1.01769	1	1	2025-05-06 12:11:08.486781	1	1
300	20	15	20	336.73	1.01019	1	1	2025-05-06 12:11:08.486781	1	1
301	1	16	1	161.33	0.48399	1	1	2025-05-06 12:11:08.486781	2	1
302	2	16	2	163.83	0.49149	1	1	2025-05-06 12:11:08.486781	2	1
303	3	16	3	166.33	1.49697	3	3	2025-05-06 12:11:08.486781	2	1
304	4	16	4	168.83	1.51947	3	3	2025-05-06 12:11:08.486781	2	1
305	5	16	5	171.33	1.02798	2	2	2025-05-06 12:11:08.486781	2	1
306	6	16	6	173.83	1.04298	2	2	2025-05-06 12:11:08.486781	2	1
307	7	16	7	176.33	1.05798	2	2	2025-05-06 12:11:08.486781	2	1
308	8	16	8	178.83	0.53649	1	1	2025-05-06 12:11:08.486781	2	1
309	9	16	9	181.33	1.63197	3	3	2025-05-06 12:11:08.486781	2	1
310	10	16	10	183.83	1.65447	3	3	2025-05-06 12:11:08.486781	2	1
311	11	16	11	156.33	1.40697	3	3	2025-05-06 12:11:08.486781	1	1
312	12	16	12	153.83	1.38447	3	3	2025-05-06 12:11:08.486781	1	1
313	13	16	13	151.33	1.36197	3	3	2025-05-06 12:11:08.486781	1	1
314	14	16	14	148.83	0.44649	1	1	2025-05-06 12:11:08.486781	1	1
315	15	16	15	146.33	0.43899	1	1	2025-05-06 12:11:08.486781	1	1
316	16	16	16	143.83	1.29447	3	3	2025-05-06 12:11:08.486781	1	1
317	17	16	17	141.33	0.84798	2	2	2025-05-06 12:11:08.486781	1	1
318	18	16	18	138.83	0.41649	1	1	2025-05-06 12:11:08.486781	1	1
319	19	16	19	136.33	0.81798	2	2	2025-05-06 12:11:08.486781	1	1
320	20	16	20	133.83	1.20447	3	3	2025-05-06 12:11:08.486781	1	1
321	1	17	1	1017.39	9.15651	3	3	2025-05-06 12:11:08.486781	2	1
322	2	17	2	1019.89	6.11934	2	2	2025-05-06 12:11:08.486781	2	1
323	3	17	3	1022.39	3.06717	1	1	2025-05-06 12:11:08.486781	2	1
324	4	17	4	1024.89	6.14934	2	2	2025-05-06 12:11:08.486781	2	1
325	5	17	5	1027.39	3.08217	1	1	2025-05-06 12:11:08.486781	2	1
326	6	17	6	1029.89	3.08967	1	1	2025-05-06 12:11:08.486781	2	1
327	7	17	7	1032.39	6.19434	2	2	2025-05-06 12:11:08.486781	2	1
328	8	17	8	1034.89	9.31401	3	3	2025-05-06 12:11:08.486781	2	1
329	9	17	9	1037.39	3.11217	1	1	2025-05-06 12:11:08.486781	2	1
330	10	17	10	1039.89	3.11967	1	1	2025-05-06 12:11:08.486781	2	1
331	11	17	11	1012.39	3.03717	1	1	2025-05-06 12:11:08.486781	1	1
332	12	17	12	1009.89	9.08901	3	3	2025-05-06 12:11:08.486781	1	1
333	13	17	13	1007.39	3.02217	1	1	2025-05-06 12:11:08.486781	1	1
334	14	17	14	1004.89	9.04401	3	3	2025-05-06 12:11:08.486781	1	1
335	15	17	15	1002.39	3.00717	1	1	2025-05-06 12:11:08.486781	1	1
336	16	17	16	999.89	8.99901	3	3	2025-05-06 12:11:08.486781	1	1
337	17	17	17	997.39	8.97651	3	3	2025-05-06 12:11:08.486781	1	1
338	18	17	18	994.89	8.95401	3	3	2025-05-06 12:11:08.486781	1	1
339	19	17	19	992.39	2.97717	1	1	2025-05-06 12:11:08.486781	1	1
340	20	17	20	989.89	5.93934	2	2	2025-05-06 12:11:08.486781	1	1
341	1	18	1	74.20	0.22260	1	1	2025-05-06 12:11:08.486781	2	1
342	2	18	2	76.70	0.46020	2	2	2025-05-06 12:11:08.486781	2	1
343	3	18	3	79.20	0.71280	3	3	2025-05-06 12:11:08.486781	2	1
344	4	18	4	81.70	0.73530	3	3	2025-05-06 12:11:08.486781	2	1
345	5	18	5	84.20	0.50520	2	2	2025-05-06 12:11:08.486781	2	1
346	6	18	6	86.70	0.26010	1	1	2025-05-06 12:11:08.486781	2	1
347	7	18	7	89.20	0.80280	3	3	2025-05-06 12:11:08.486781	2	1
348	8	18	8	91.70	0.55020	2	2	2025-05-06 12:11:08.486781	2	1
349	9	18	9	94.20	0.56520	2	2	2025-05-06 12:11:08.486781	2	1
350	10	18	10	96.70	0.29010	1	1	2025-05-06 12:11:08.486781	2	1
351	11	18	11	69.20	0.20760	1	1	2025-05-06 12:11:08.486781	1	1
352	12	18	12	66.70	0.20010	1	1	2025-05-06 12:11:08.486781	1	1
353	13	18	13	64.20	0.19260	1	1	2025-05-06 12:11:08.486781	1	1
354	14	18	14	61.70	0.18510	1	1	2025-05-06 12:11:08.486781	1	1
355	15	18	15	59.20	0.53280	3	3	2025-05-06 12:11:08.486781	1	1
356	16	18	16	56.70	0.51030	3	3	2025-05-06 12:11:08.486781	1	1
357	17	18	17	54.20	0.16260	1	1	2025-05-06 12:11:08.486781	1	1
358	18	18	18	51.70	0.15510	1	1	2025-05-06 12:11:08.486781	1	1
359	19	18	19	49.20	0.29520	2	2	2025-05-06 12:11:08.486781	1	1
360	20	18	20	46.70	0.14010	1	1	2025-05-06 12:11:08.486781	1	1
361	1	19	1	134.49	0.40347	1	1	2025-05-06 12:11:08.486781	2	1
362	2	19	2	136.99	0.41097	1	1	2025-05-06 12:11:08.486781	2	1
363	3	19	3	139.49	0.41847	1	1	2025-05-06 12:11:08.486781	2	1
364	4	19	4	141.99	1.27791	3	3	2025-05-06 12:11:08.486781	2	1
365	5	19	5	144.49	1.30041	3	3	2025-05-06 12:11:08.486781	2	1
366	6	19	6	146.99	1.32291	3	3	2025-05-06 12:11:08.486781	2	1
367	7	19	7	149.49	1.34541	3	3	2025-05-06 12:11:08.486781	2	1
368	8	19	8	151.99	0.91194	2	2	2025-05-06 12:11:08.486781	2	1
369	9	19	9	154.49	0.92694	2	2	2025-05-06 12:11:08.486781	2	1
370	10	19	10	156.99	0.94194	2	2	2025-05-06 12:11:08.486781	2	1
371	11	19	11	129.49	0.77694	2	2	2025-05-06 12:11:08.486781	1	1
372	12	19	12	126.99	1.14291	3	3	2025-05-06 12:11:08.486781	1	1
373	13	19	13	124.49	1.12041	3	3	2025-05-06 12:11:08.486781	1	1
374	14	19	14	121.99	0.73194	2	2	2025-05-06 12:11:08.486781	1	1
375	15	19	15	119.49	0.35847	1	1	2025-05-06 12:11:08.486781	1	1
376	16	19	16	116.99	0.35097	1	1	2025-05-06 12:11:08.486781	1	1
377	17	19	17	114.49	0.34347	1	1	2025-05-06 12:11:08.486781	1	1
378	18	19	18	111.99	0.33597	1	1	2025-05-06 12:11:08.486781	1	1
379	19	19	19	109.49	0.98541	3	3	2025-05-06 12:11:08.486781	1	1
380	20	19	20	106.99	0.96291	3	3	2025-05-06 12:11:08.486781	1	1
381	1	20	1	61.82	0.55638	3	3	2025-05-06 12:11:08.486781	2	1
382	2	20	2	64.32	0.38592	2	2	2025-05-06 12:11:08.486781	2	1
383	3	20	3	66.82	0.60138	3	3	2025-05-06 12:11:08.486781	2	1
384	4	20	4	69.32	0.41592	2	2	2025-05-06 12:11:08.486781	2	1
385	5	20	5	71.82	0.43092	2	2	2025-05-06 12:11:08.486781	2	1
386	6	20	6	74.32	0.66888	3	3	2025-05-06 12:11:08.486781	2	1
387	7	20	7	76.82	0.23046	1	1	2025-05-06 12:11:08.486781	2	1
388	8	20	8	79.32	0.71388	3	3	2025-05-06 12:11:08.486781	2	1
389	9	20	9	81.82	0.24546	1	1	2025-05-06 12:11:08.486781	2	1
390	10	20	10	84.32	0.50592	2	2	2025-05-06 12:11:08.486781	2	1
391	11	20	11	56.82	0.34092	2	2	2025-05-06 12:11:08.486781	1	1
392	12	20	12	54.32	0.48888	3	3	2025-05-06 12:11:08.486781	1	1
393	13	20	13	51.82	0.31092	2	2	2025-05-06 12:11:08.486781	1	1
394	14	20	14	49.32	0.14796	1	1	2025-05-06 12:11:08.486781	1	1
395	15	20	15	46.82	0.14046	1	1	2025-05-06 12:11:08.486781	1	1
396	16	20	16	44.32	0.26592	2	2	2025-05-06 12:11:08.486781	1	1
397	17	20	17	41.82	0.12546	1	1	2025-05-06 12:11:08.486781	1	1
398	18	20	18	39.32	0.23592	2	2	2025-05-06 12:11:08.486781	1	1
399	19	20	19	36.82	0.22092	2	2	2025-05-06 12:11:08.486781	1	1
400	20	20	20	34.32	0.10296	1	1	2025-05-06 12:11:08.486781	1	1
402	2	21	2	386.06	2.31636	2	2	2025-05-06 12:11:08.486781	2	1
403	3	21	3	388.56	2.33136	2	2	2025-05-06 12:11:08.486781	2	1
404	4	21	4	391.06	3.51954	3	3	2025-05-06 12:11:08.486781	2	1
405	5	21	5	393.56	1.18068	1	1	2025-05-06 12:11:08.486781	2	1
406	6	21	6	396.06	3.56454	3	3	2025-05-06 12:11:08.486781	2	1
407	7	21	7	398.56	1.19568	1	1	2025-05-06 12:11:08.486781	2	1
408	8	21	8	401.06	2.40636	2	2	2025-05-06 12:11:08.486781	2	1
409	9	21	9	403.56	3.63204	3	3	2025-05-06 12:11:08.486781	2	1
410	10	21	10	406.06	2.43636	2	2	2025-05-06 12:11:08.486781	2	1
411	11	21	11	378.56	2.27136	2	2	2025-05-06 12:11:08.486781	1	1
412	12	21	12	376.06	2.25636	2	2	2025-05-06 12:11:08.486781	1	1
413	13	21	13	373.56	1.12068	1	1	2025-05-06 12:11:08.486781	1	1
414	14	21	14	371.06	2.22636	2	2	2025-05-06 12:11:08.486781	1	1
415	15	21	15	368.56	2.21136	2	2	2025-05-06 12:11:08.486781	1	1
416	16	21	16	366.06	2.19636	2	2	2025-05-06 12:11:08.486781	1	1
417	17	21	17	363.56	3.27204	3	3	2025-05-06 12:11:08.486781	1	1
418	18	21	18	361.06	1.08318	1	1	2025-05-06 12:11:08.486781	1	1
419	19	21	19	358.56	2.15136	2	2	2025-05-06 12:11:08.486781	1	1
420	20	21	20	356.06	1.06818	1	1	2025-05-06 12:11:08.486781	1	1
421	1	22	1	22.77	0.20493	3	3	2025-05-06 12:11:08.486781	2	1
422	2	22	2	25.27	0.15162	2	2	2025-05-06 12:11:08.486781	2	1
423	3	22	3	27.77	0.16662	2	2	2025-05-06 12:11:08.486781	2	1
424	4	22	4	30.27	0.09081	1	1	2025-05-06 12:11:08.486781	2	1
425	5	22	5	32.77	0.19662	2	2	2025-05-06 12:11:08.486781	2	1
426	6	22	6	35.27	0.21162	2	2	2025-05-06 12:11:08.486781	2	1
427	7	22	7	37.77	0.33993	3	3	2025-05-06 12:11:08.486781	2	1
428	8	22	8	40.27	0.24162	2	2	2025-05-06 12:11:08.486781	2	1
429	9	22	9	42.77	0.25662	2	2	2025-05-06 12:11:08.486781	2	1
430	10	22	10	45.27	0.27162	2	2	2025-05-06 12:11:08.486781	2	1
431	11	22	11	17.77	0.10662	2	2	2025-05-06 12:11:08.486781	1	1
432	12	22	12	15.27	0.04581	1	1	2025-05-06 12:11:08.486781	1	1
433	13	22	13	12.77	0.07662	2	2	2025-05-06 12:11:08.486781	1	1
434	14	22	14	10.27	0.03081	1	1	2025-05-06 12:11:08.486781	1	1
435	15	22	15	7.77	0.06993	3	3	2025-05-06 12:11:08.486781	1	1
436	16	22	16	5.27	0.03162	2	2	2025-05-06 12:11:08.486781	1	1
437	17	22	17	2.77	0.02493	3	3	2025-05-06 12:11:08.486781	1	1
438	18	22	18	0.27	0.00081	1	1	2025-05-06 12:11:08.486781	1	1
439	19	22	19	-2.23	-0.00669	1	1	2025-05-06 12:11:08.486781	1	1
440	20	22	20	-4.73	-0.04257	3	3	2025-05-06 12:11:08.486781	1	1
441	1	23	1	1136.56	10.22904	3	3	2025-05-06 12:11:08.486781	2	1
442	2	23	2	1139.06	6.83436	2	2	2025-05-06 12:11:08.486781	2	1
443	3	23	3	1141.56	10.27404	3	3	2025-05-06 12:11:08.486781	2	1
444	4	23	4	1144.06	10.29654	3	3	2025-05-06 12:11:08.486781	2	1
445	5	23	5	1146.56	10.31904	3	3	2025-05-06 12:11:08.486781	2	1
446	6	23	6	1149.06	10.34154	3	3	2025-05-06 12:11:08.486781	2	1
447	7	23	7	1151.56	10.36404	3	3	2025-05-06 12:11:08.486781	2	1
448	8	23	8	1154.06	3.46218	1	1	2025-05-06 12:11:08.486781	2	1
449	9	23	9	1156.56	3.46968	1	1	2025-05-06 12:11:08.486781	2	1
450	10	23	10	1159.06	3.47718	1	1	2025-05-06 12:11:08.486781	2	1
451	11	23	11	1131.56	6.78936	2	2	2025-05-06 12:11:08.486781	1	1
452	12	23	12	1129.06	3.38718	1	1	2025-05-06 12:11:08.486781	1	1
453	13	23	13	1126.56	6.75936	2	2	2025-05-06 12:11:08.486781	1	1
454	14	23	14	1124.06	6.74436	2	2	2025-05-06 12:11:08.486781	1	1
455	15	23	15	1121.56	10.09404	3	3	2025-05-06 12:11:08.486781	1	1
456	16	23	16	1119.06	6.71436	2	2	2025-05-06 12:11:08.486781	1	1
457	17	23	17	1116.56	3.34968	1	1	2025-05-06 12:11:08.486781	1	1
458	18	23	18	1114.06	10.02654	3	3	2025-05-06 12:11:08.486781	1	1
459	19	23	19	1111.56	6.66936	2	2	2025-05-06 12:11:08.486781	1	1
460	20	23	20	1109.06	6.65436	2	2	2025-05-06 12:11:08.486781	1	1
461	1	24	1	103.09	0.30927	1	1	2025-05-06 12:11:08.486781	2	1
462	2	24	2	105.59	0.63354	2	2	2025-05-06 12:11:08.486781	2	1
463	3	24	3	108.09	0.97281	3	3	2025-05-06 12:11:08.486781	2	1
464	4	24	4	110.59	0.99531	3	3	2025-05-06 12:11:08.486781	2	1
465	5	24	5	113.09	0.67854	2	2	2025-05-06 12:11:08.486781	2	1
466	6	24	6	115.59	1.04031	3	3	2025-05-06 12:11:08.486781	2	1
467	7	24	7	118.09	0.35427	1	1	2025-05-06 12:11:08.486781	2	1
468	8	24	8	120.59	1.08531	3	3	2025-05-06 12:11:08.486781	2	1
469	9	24	9	123.09	0.36927	1	1	2025-05-06 12:11:08.486781	2	1
470	10	24	10	125.59	0.37677	1	1	2025-05-06 12:11:08.486781	2	1
471	11	24	11	98.09	0.58854	2	2	2025-05-06 12:11:08.486781	1	1
472	12	24	12	95.59	0.28677	1	1	2025-05-06 12:11:08.486781	1	1
473	13	24	13	93.09	0.27927	1	1	2025-05-06 12:11:08.486781	1	1
474	14	24	14	90.59	0.81531	3	3	2025-05-06 12:11:08.486781	1	1
475	15	24	15	88.09	0.26427	1	1	2025-05-06 12:11:08.486781	1	1
476	16	24	16	85.59	0.25677	1	1	2025-05-06 12:11:08.486781	1	1
477	17	24	17	83.09	0.24927	1	1	2025-05-06 12:11:08.486781	1	1
478	18	24	18	80.59	0.48354	2	2	2025-05-06 12:11:08.486781	1	1
479	19	24	19	78.09	0.70281	3	3	2025-05-06 12:11:08.486781	1	1
480	20	24	20	75.59	0.68031	3	3	2025-05-06 12:11:08.486781	1	1
481	1	25	1	141.94	0.85164	2	2	2025-05-06 12:11:08.486781	2	1
482	2	25	2	144.44	0.86664	2	2	2025-05-06 12:11:08.486781	2	1
483	3	25	3	146.94	0.88164	2	2	2025-05-06 12:11:08.486781	2	1
484	4	25	4	149.44	1.34496	3	3	2025-05-06 12:11:08.486781	2	1
485	5	25	5	151.94	0.45582	1	1	2025-05-06 12:11:08.486781	2	1
486	6	25	6	154.44	0.92664	2	2	2025-05-06 12:11:08.486781	2	1
487	7	25	7	156.94	1.41246	3	3	2025-05-06 12:11:08.486781	2	1
488	8	25	8	159.44	0.47832	1	1	2025-05-06 12:11:08.486781	2	1
489	9	25	9	161.94	1.45746	3	3	2025-05-06 12:11:08.486781	2	1
490	10	25	10	164.44	0.98664	2	2	2025-05-06 12:11:08.486781	2	1
491	11	25	11	136.94	1.23246	3	3	2025-05-06 12:11:08.486781	1	1
492	12	25	12	134.44	0.40332	1	1	2025-05-06 12:11:08.486781	1	1
493	13	25	13	131.94	1.18746	3	3	2025-05-06 12:11:08.486781	1	1
494	14	25	14	129.44	0.77664	2	2	2025-05-06 12:11:08.486781	1	1
495	15	25	15	126.94	0.76164	2	2	2025-05-06 12:11:08.486781	1	1
496	16	25	16	124.44	0.74664	2	2	2025-05-06 12:11:08.486781	1	1
497	17	25	17	121.94	0.73164	2	2	2025-05-06 12:11:08.486781	1	1
498	18	25	18	119.44	0.35832	1	1	2025-05-06 12:11:08.486781	1	1
499	19	25	19	116.94	1.05246	3	3	2025-05-06 12:11:08.486781	1	1
500	20	25	20	114.44	0.68664	2	2	2025-05-06 12:11:08.486781	1	1
501	1	26	1	203.22	0.60966	1	1	2025-05-06 12:11:08.486781	2	1
502	2	26	2	205.72	0.61716	1	1	2025-05-06 12:11:08.486781	2	1
503	3	26	3	208.22	0.62466	1	1	2025-05-06 12:11:08.486781	2	1
504	4	26	4	210.72	0.63216	1	1	2025-05-06 12:11:08.486781	2	1
505	5	26	5	213.22	1.91898	3	3	2025-05-06 12:11:08.486781	2	1
506	6	26	6	215.72	1.94148	3	3	2025-05-06 12:11:08.486781	2	1
507	7	26	7	218.22	0.65466	1	1	2025-05-06 12:11:08.486781	2	1
508	8	26	8	220.72	1.32432	2	2	2025-05-06 12:11:08.486781	2	1
509	9	26	9	223.22	0.66966	1	1	2025-05-06 12:11:08.486781	2	1
510	10	26	10	225.72	1.35432	2	2	2025-05-06 12:11:08.486781	2	1
511	11	26	11	198.22	1.78398	3	3	2025-05-06 12:11:08.486781	1	1
512	12	26	12	195.72	0.58716	1	1	2025-05-06 12:11:08.486781	1	1
513	13	26	13	193.22	0.57966	1	1	2025-05-06 12:11:08.486781	1	1
514	14	26	14	190.72	1.14432	2	2	2025-05-06 12:11:08.486781	1	1
515	15	26	15	188.22	1.12932	2	2	2025-05-06 12:11:08.486781	1	1
516	16	26	16	185.72	1.11432	2	2	2025-05-06 12:11:08.486781	1	1
517	17	26	17	183.22	1.09932	2	2	2025-05-06 12:11:08.486781	1	1
518	18	26	18	180.72	1.08432	2	2	2025-05-06 12:11:08.486781	1	1
519	19	26	19	178.22	0.53466	1	1	2025-05-06 12:11:08.486781	1	1
520	20	26	20	175.72	0.52716	1	1	2025-05-06 12:11:08.486781	1	1
521	1	27	1	250.80	1.50480	2	2	2025-05-06 12:11:08.486781	2	1
522	2	27	2	253.30	2.27970	3	3	2025-05-06 12:11:08.486781	2	1
523	3	27	3	255.80	2.30220	3	3	2025-05-06 12:11:08.486781	2	1
524	4	27	4	258.30	0.77490	1	1	2025-05-06 12:11:08.486781	2	1
525	5	27	5	260.80	1.56480	2	2	2025-05-06 12:11:08.486781	2	1
526	6	27	6	263.30	1.57980	2	2	2025-05-06 12:11:08.486781	2	1
527	7	27	7	265.80	1.59480	2	2	2025-05-06 12:11:08.486781	2	1
528	8	27	8	268.30	2.41470	3	3	2025-05-06 12:11:08.486781	2	1
529	9	27	9	270.80	1.62480	2	2	2025-05-06 12:11:08.486781	2	1
530	10	27	10	273.30	0.81990	1	1	2025-05-06 12:11:08.486781	2	1
531	11	27	11	245.80	1.47480	2	2	2025-05-06 12:11:08.486781	1	1
532	12	27	12	243.30	2.18970	3	3	2025-05-06 12:11:08.486781	1	1
533	13	27	13	240.80	1.44480	2	2	2025-05-06 12:11:08.486781	1	1
534	14	27	14	238.30	0.71490	1	1	2025-05-06 12:11:08.486781	1	1
535	15	27	15	235.80	1.41480	2	2	2025-05-06 12:11:08.486781	1	1
536	16	27	16	233.30	1.39980	2	2	2025-05-06 12:11:08.486781	1	1
537	17	27	17	230.80	1.38480	2	2	2025-05-06 12:11:08.486781	1	1
538	18	27	18	228.30	1.36980	2	2	2025-05-06 12:11:08.486781	1	1
539	19	27	19	225.80	2.03220	3	3	2025-05-06 12:11:08.486781	1	1
540	20	27	20	223.30	2.00970	3	3	2025-05-06 12:11:08.486781	1	1
542	2	28	2	46.12	0.41508	3	3	2025-05-06 12:11:08.486781	2	1
543	3	28	3	48.62	0.14586	1	1	2025-05-06 12:11:08.486781	2	1
544	4	28	4	51.12	0.46008	3	3	2025-05-06 12:11:08.486781	2	1
545	5	28	5	53.62	0.48258	3	3	2025-05-06 12:11:08.486781	2	1
546	6	28	6	56.12	0.50508	3	3	2025-05-06 12:11:08.486781	2	1
547	7	28	7	58.62	0.17586	1	1	2025-05-06 12:11:08.486781	2	1
548	8	28	8	61.12	0.18336	1	1	2025-05-06 12:11:08.486781	2	1
549	9	28	9	63.62	0.38172	2	2	2025-05-06 12:11:08.486781	2	1
550	10	28	10	66.12	0.59508	3	3	2025-05-06 12:11:08.486781	2	1
551	11	28	11	38.62	0.34758	3	3	2025-05-06 12:11:08.486781	1	1
552	12	28	12	36.12	0.32508	3	3	2025-05-06 12:11:08.486781	1	1
553	13	28	13	33.62	0.30258	3	3	2025-05-06 12:11:08.486781	1	1
554	14	28	14	31.12	0.18672	2	2	2025-05-06 12:11:08.486781	1	1
555	15	28	15	28.62	0.17172	2	2	2025-05-06 12:11:08.486781	1	1
556	16	28	16	26.12	0.07836	1	1	2025-05-06 12:11:08.486781	1	1
557	17	28	17	23.62	0.21258	3	3	2025-05-06 12:11:08.486781	1	1
558	18	28	18	21.12	0.06336	1	1	2025-05-06 12:11:08.486781	1	1
559	19	28	19	18.62	0.05586	1	1	2025-05-06 12:11:08.486781	1	1
560	20	28	20	16.12	0.09672	2	2	2025-05-06 12:11:08.486781	1	1
561	1	29	1	562.06	5.05854	3	3	2025-05-06 12:11:08.486781	2	1
562	2	29	2	564.56	1.69368	1	1	2025-05-06 12:11:08.486781	2	1
563	3	29	3	567.06	1.70118	1	1	2025-05-06 12:11:08.486781	2	1
564	4	29	4	569.56	1.70868	1	1	2025-05-06 12:11:08.486781	2	1
565	5	29	5	572.06	3.43236	2	2	2025-05-06 12:11:08.486781	2	1
566	6	29	6	574.56	5.17104	3	3	2025-05-06 12:11:08.486781	2	1
567	7	29	7	577.06	1.73118	1	1	2025-05-06 12:11:08.486781	2	1
568	8	29	8	579.56	3.47736	2	2	2025-05-06 12:11:08.486781	2	1
569	9	29	9	582.06	5.23854	3	3	2025-05-06 12:11:08.486781	2	1
570	10	29	10	584.56	5.26104	3	3	2025-05-06 12:11:08.486781	2	1
571	11	29	11	557.06	5.01354	3	3	2025-05-06 12:11:08.486781	1	1
572	12	29	12	554.56	1.66368	1	1	2025-05-06 12:11:08.486781	1	1
573	13	29	13	552.06	4.96854	3	3	2025-05-06 12:11:08.486781	1	1
574	14	29	14	549.56	1.64868	1	1	2025-05-06 12:11:08.486781	1	1
575	15	29	15	547.06	3.28236	2	2	2025-05-06 12:11:08.486781	1	1
576	16	29	16	544.56	3.26736	2	2	2025-05-06 12:11:08.486781	1	1
577	17	29	17	542.06	3.25236	2	2	2025-05-06 12:11:08.486781	1	1
578	18	29	18	539.56	1.61868	1	1	2025-05-06 12:11:08.486781	1	1
579	19	29	19	537.06	3.22236	2	2	2025-05-06 12:11:08.486781	1	1
580	20	29	20	534.56	4.81104	3	3	2025-05-06 12:11:08.486781	1	1
581	1	30	1	85.34	0.51204	2	2	2025-05-06 12:11:08.486781	2	1
582	2	30	2	87.84	0.52704	2	2	2025-05-06 12:11:08.486781	2	1
583	3	30	3	90.34	0.54204	2	2	2025-05-06 12:11:08.486781	2	1
584	4	30	4	92.84	0.27852	1	1	2025-05-06 12:11:08.486781	2	1
585	5	30	5	95.34	0.57204	2	2	2025-05-06 12:11:08.486781	2	1
586	6	30	6	97.84	0.88056	3	3	2025-05-06 12:11:08.486781	2	1
587	7	30	7	100.34	0.90306	3	3	2025-05-06 12:11:08.486781	2	1
588	8	30	8	102.84	0.61704	2	2	2025-05-06 12:11:08.486781	2	1
589	9	30	9	105.34	0.63204	2	2	2025-05-06 12:11:08.486781	2	1
590	10	30	10	107.84	0.32352	1	1	2025-05-06 12:11:08.486781	2	1
591	11	30	11	80.34	0.48204	2	2	2025-05-06 12:11:08.486781	1	1
592	12	30	12	77.84	0.46704	2	2	2025-05-06 12:11:08.486781	1	1
593	13	30	13	75.34	0.45204	2	2	2025-05-06 12:11:08.486781	1	1
594	14	30	14	72.84	0.43704	2	2	2025-05-06 12:11:08.486781	1	1
595	15	30	15	70.34	0.42204	2	2	2025-05-06 12:11:08.486781	1	1
596	16	30	16	67.84	0.20352	1	1	2025-05-06 12:11:08.486781	1	1
597	17	30	17	65.34	0.39204	2	2	2025-05-06 12:11:08.486781	1	1
598	18	30	18	62.84	0.56556	3	3	2025-05-06 12:11:08.486781	1	1
599	19	30	19	60.34	0.54306	3	3	2025-05-06 12:11:08.486781	1	1
600	20	30	20	57.84	0.52056	3	3	2025-05-06 12:11:08.486781	1	1
601	34	21	32	395.00	1.18500	1	\N	2025-05-11 13:37:36.433064	1	2
401	1	21	1	383.56	2.30136	2	1	2025-05-06 12:11:08.486781	2	3
602	35	28	34	44.38	0.13314	1	\N	2025-05-16 11:59:02.712589	1	2
541	1	28	1	43.62	0.26172	2	1	2025-05-06 12:11:08.486781	2	3
603	35	1	34	211.45	0.63435	1	\N	2025-05-16 12:00:40.676007	1	2
1	1	1	1	201.39	1.20834	2	1	2025-05-06 12:11:08.486781	2	3
604	35	21	34	4.69	0.01407	1	1	2025-05-16 12:00:53.163476	1	1
\.


--
-- Data for Name: savings_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.savings_accounts (id, customer_account_id, savings_account_number, currency_id, balance, reserved_amount) FROM stdin;
2	2	13827802111912004142304	1	29116.87	0.00000
3	3	507049192141341	1	54910.03	0.00000
4	4	77644381986197116992	1	80218.77	0.00000
5	5	70191301040601	1	95207.18	0.00000
6	6	20686596223013795	1	92741.05	0.00000
7	7	12480008565	1	81618.66	0.00000
8	8	560984219672317168594	1	32500.89	0.00000
9	9	9524984957984022468203	1	54199.72	0.00000
10	10	379456512195816031	1	36904.98	0.00000
11	11	3487208491595109254	1	40472.82	0.00000
12	12	6520536508425860	1	37520.09	0.00000
13	13	25345094999920	1	67597.31	0.00000
14	14	31153951808901140	1	78966.25	0.00000
15	15	32613777920697886225680054837	1	26580.49	0.00000
16	16	518772634658766150781	1	44584.71	0.00000
17	17	998926336610721748	1	66640.49	0.00000
18	18	71502948549139284793654983464	1	76506.91	0.00000
19	19	6505692584	1	21218.12	0.00000
20	20	921138285123	1	30348.29	0.00000
21	21	089760021678467	1	55470.26	0.00000
22	22	691603877299086792883966	1	53956.23	0.00000
23	23	9352927510236859009302190203	1	61006.38	0.00000
24	24	542238567458195140585487050	1	68200.03	0.00000
25	25	520887953290772	1	98179.84	0.00000
26	26	581535206341249	1	80879.93	0.00000
27	27	9998193639	1	39962.21	0.00000
28	28	988489747331632079699887	1	69728.46	0.00000
29	29	847295276472204789829509340889	1	33856.69	0.00000
30	30	58975127618336635435484148	1	73810.95	0.00000
32	34	8104780435088039204450612	1	1615.29	0.00000
33	34	5780356398023142950	2	100.00	0.00000
1	1	865447751279612180033026976	1	41740.50	0.00000
34	35	1588888844321330754856307	1	731.26	15.55653
\.


--
-- Data for Name: securities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.securities (id, security_type, ticker, isin, company_name, stock_exchange, currency_id, last_price, updated_at) FROM stdin;
1	1	AAPL	US0378331005	Apple Inc.	2	1	211.45	2025-05-16 12:05:42.812521
2	1	MSFT	US5949181045	Microsoft Corporation	2	1	453.13	2025-05-16 12:05:42.967492
16	1	PG	US7427181091	The Procter & Gamble Company	1	1	162.41	2025-05-16 12:05:43.130701
17	1	COST	US22160K1051	Costco Wholesale Corporation	2	1	1010.47	2025-05-16 12:05:43.285488
18	1	KO	US1912161007	The Coca-Cola Company	1	1	71.61	2025-05-16 12:05:43.465793
7	1	TSLA	US88160R1014	Tesla, Inc.	2	1	342.82	2025-05-16 12:05:43.629223
25	1	QCOM	US7475251036	Qualcomm Incorporated	2	1	152.61	2025-05-16 12:05:43.79967
19	1	PEP	US7134481081	PepsiCo, Inc.	2	1	131.50	2025-05-16 12:05:43.965555
20	1	CSCO	US17275R1023	Cisco Systems, Inc.	2	1	64.26	2025-05-16 12:05:44.118955
27	1	TMUS	US8725901040	T-Mobile US, Inc.	2	1	240.16	2025-05-16 12:05:44.287399
28	1	BAC	US0605051046	Bank of America Corporation	1	1	44.38	2025-05-16 12:05:44.47738
29	1	GS	US38141G1040	The Goldman Sachs Group, Inc.	1	1	615.90	2025-05-16 12:05:44.627606
30	1	MRK	US58933Y1055	Merck & Co., Inc.	1	1	74.80	2025-05-16 12:05:44.80475
4	1	AMZN	US0231351067	Amazon.com, Inc.	2	1	205.17	2025-05-16 12:05:45.022381
5	1	GOOGL	US02079K3059	Alphabet Inc. Class A	2	1	163.96	2025-05-16 12:05:45.182976
3	1	NVDA	US67066G1040	NVIDIA Corporation	2	1	134.83	2025-05-16 12:05:45.349081
23	1	NFLX	US64110L1061	Netflix, Inc.	2	1	1177.98	2025-05-16 12:05:45.501664
24	1	AMD	US0079031078	Advanced Micro Devices, Inc.	2	1	114.99	2025-05-16 12:05:45.656725
11	1	WMT	US9311421039	Walmart Inc.	1	1	96.35	2025-05-16 12:05:45.809073
13	1	V	US92826C8394	Visa Inc.	1	1	362.30	2025-05-16 12:05:45.959741
14	1	MA	US57636Q1040	Mastercard Incorporated	1	1	582.20	2025-05-16 12:05:46.110981
6	1	META	US30303M1027	Meta Platforms, Inc.	2	1	643.88	2025-05-16 12:05:46.262711
12	1	UNH	US91324P1021	UnitedHealth Group Incorporated	1	1	274.35	2025-05-16 12:05:46.457489
15	1	HD	US4370761029	The Home Depot, Inc.	1	1	378.63	2025-05-16 12:05:46.609943
26	1	AVGO	US11135F1012	Broadcom Inc.	2	1	232.64	2025-05-16 12:05:46.768852
8	1	BRK.A	US0846701086	Berkshire Hathaway Inc.	1	1	759100.00	2025-05-16 12:05:46.924394
9	1	LLY	US5324571083	Eli Lilly and Company	1	1	733.29	2025-05-16 12:05:47.077901
10	1	JPM	US46625H1005	JPMorgan Chase & Co.	1	1	267.49	2025-05-16 12:05:47.225974
21	1	ADBE	US00724F1012	Adobe Inc.	2	1	404.69	2025-05-16 12:05:47.401753
22	1	INTC	US4581401001	Intel Corporation	2	1	21.55	2025-05-16 12:05:47.562529
\.


--
-- Data for Name: security_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.security_types (id, security_type) FROM stdin;
1	Stock
2	Bond
\.


--
-- Data for Name: stock_exchanges; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock_exchanges (id, stock_exchange) FROM stdin;
1	NYSE
2	NASDAQ
4	EN
5	MOEX
3	LSE
\.


--
-- Data for Name: stocks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stocks (id, dividend_declaration_date, ex_dividend_date, divident_payment_date, divident_amount, dividend_currency_id) FROM stdin;
\.


--
-- Data for Name: transaction_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transaction_types (id, transaction_type) FROM stdin;
1	DEPOSIT
2	WITHDRAWAL
\.


--
-- Data for Name: transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.transactions (id, buy_order_id, sell_order_id, quantity, executed_price, executed_fee, executed_at) FROM stdin;
1	601	401	1	383.56	1.15068	2025-05-11 13:37:36.433064
2	602	541	1	43.62	0.13086	2025-05-16 11:59:02.712589
3	603	1	1	201.39	0.60417	2025-05-16 12:00:40.676007
\.


--
-- Name: balance_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.balance_history_id_seq', 34, true);


--
-- Name: bonds_payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bonds_payments_id_seq', 1, false);


--
-- Name: currencies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.currencies_id_seq', 5, true);


--
-- Name: customer_accounts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customer_accounts_id_seq', 35, true);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_id_seq', 35, true);


--
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_id_seq', 604, true);


--
-- Name: savings_accounts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.savings_accounts_id_seq', 34, true);


--
-- Name: securities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.securities_id_seq', 1, false);


--
-- Name: transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.transactions_id_seq', 3, true);


--
-- Name: balance_history balance_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.balance_history
    ADD CONSTRAINT balance_history_pkey PRIMARY KEY (id);


--
-- Name: bond_payment_types bond_payment_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bond_payment_types
    ADD CONSTRAINT bond_payment_types_pkey PRIMARY KEY (id);


--
-- Name: bonds_payments bonds_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds_payments
    ADD CONSTRAINT bonds_payments_pkey PRIMARY KEY (id);


--
-- Name: bonds bonds_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds
    ADD CONSTRAINT bonds_pkey PRIMARY KEY (id);


--
-- Name: currencies currencies_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT currencies_code_key UNIQUE (code);


--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.currencies
    ADD CONSTRAINT currencies_pkey PRIMARY KEY (id);


--
-- Name: customer_portfolios current_portfolio_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_portfolios
    ADD CONSTRAINT current_portfolio_pkey PRIMARY KEY (customer_account_id, security_id);


--
-- Name: customer_accounts customer_accounts_email_login_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_email_login_key UNIQUE (email, login);


--
-- Name: customer_accounts customer_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: order_status order_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_status
    ADD CONSTRAINT order_status_pkey PRIMARY KEY (id);


--
-- Name: order_type order_type_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_type
    ADD CONSTRAINT order_type_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: savings_accounts savings_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts
    ADD CONSTRAINT savings_accounts_pkey PRIMARY KEY (id);


--
-- Name: savings_accounts savings_accounts_savings_account_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts
    ADD CONSTRAINT savings_accounts_savings_account_number_key UNIQUE (savings_account_number);


--
-- Name: securities securities_isin_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities
    ADD CONSTRAINT securities_isin_key UNIQUE (isin);


--
-- Name: securities securities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities
    ADD CONSTRAINT securities_pkey PRIMARY KEY (id);


--
-- Name: security_types security_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.security_types
    ADD CONSTRAINT security_types_pkey PRIMARY KEY (id);


--
-- Name: security_types security_types_security_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.security_types
    ADD CONSTRAINT security_types_security_type_key UNIQUE (security_type);


--
-- Name: stock_exchanges stock_exchanges_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock_exchanges
    ADD CONSTRAINT stock_exchanges_pkey PRIMARY KEY (id);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


--
-- Name: transaction_types transaction_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transaction_types
    ADD CONSTRAINT transaction_types_pkey PRIMARY KEY (id);


--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT transactions_pkey PRIMARY KEY (id);


--
-- Name: savings_accounts unique_currency_for_customer_account; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts
    ADD CONSTRAINT unique_currency_for_customer_account UNIQUE (customer_account_id, currency_id);


--
-- Name: transactions uq_transactions_buy_sell; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT uq_transactions_buy_sell UNIQUE (buy_order_id, sell_order_id);


--
-- Name: idx_balance_history_savings_account_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_balance_history_savings_account_id ON public.balance_history USING btree (savings_account_id);


--
-- Name: idx_bonds_payments_bond_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bonds_payments_bond_id ON public.bonds_payments USING btree (bond_id);


--
-- Name: idx_orders_customer_account_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_customer_account_id ON public.orders USING btree (customer_account_id);


--
-- Name: idx_orders_order_status_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_order_status_id ON public.orders USING btree (order_status_id);


--
-- Name: idx_orders_order_type_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_order_type_id ON public.orders USING btree (order_type_id);


--
-- Name: idx_orders_price; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_price ON public.orders USING btree (price);


--
-- Name: idx_orders_savings_account_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_savings_account_id ON public.orders USING btree (savings_account_id);


--
-- Name: idx_orders_security_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_security_id ON public.orders USING btree (security_id);


--
-- Name: idx_securities_last_price; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_securities_last_price ON public.securities USING btree (last_price);


--
-- Name: idx_securities_security_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_securities_security_type ON public.securities USING btree (security_type);


--
-- Name: idx_securities_stock_exchange; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_securities_stock_exchange ON public.securities USING btree (stock_exchange);


--
-- Name: idx_transactions_sell_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transactions_sell_order_id ON public.transactions USING btree (sell_order_id);


--
-- Name: ix_savings_accounts_currency; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_savings_accounts_currency ON public.savings_accounts USING btree (currency_id);


--
-- Name: orders match_order_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER match_order_trigger AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.match_order();


--
-- Name: balance_history trg_block_delete_balance_history; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_delete_balance_history BEFORE DELETE ON public.balance_history FOR EACH ROW EXECUTE FUNCTION public.block_delete();


--
-- Name: order_status trg_block_delete_order_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_delete_order_status BEFORE DELETE ON public.order_status FOR EACH ROW EXECUTE FUNCTION public.block_delete();


--
-- Name: order_type trg_block_delete_order_type; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_delete_order_type BEFORE DELETE ON public.order_type FOR EACH ROW EXECUTE FUNCTION public.block_delete();


--
-- Name: transaction_types trg_block_delete_transaction_types; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_delete_transaction_types BEFORE DELETE ON public.transaction_types FOR EACH ROW EXECUTE FUNCTION public.block_delete();


--
-- Name: transactions trg_block_delete_transactions; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_delete_transactions BEFORE DELETE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.block_delete();


--
-- Name: order_status trg_block_insert_order_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_insert_order_status BEFORE INSERT ON public.order_status FOR EACH ROW EXECUTE FUNCTION public.block_insert();


--
-- Name: order_type trg_block_insert_order_type; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_insert_order_type BEFORE INSERT ON public.order_type FOR EACH ROW EXECUTE FUNCTION public.block_insert();


--
-- Name: transaction_types trg_block_insert_transaction_types; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_insert_transaction_types BEFORE INSERT ON public.transaction_types FOR EACH ROW EXECUTE FUNCTION public.block_insert();


--
-- Name: balance_history trg_block_update_balance_history; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_update_balance_history BEFORE UPDATE ON public.balance_history FOR EACH ROW EXECUTE FUNCTION public.block_update();


--
-- Name: order_status trg_block_update_order_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_update_order_status BEFORE UPDATE ON public.order_status FOR EACH ROW EXECUTE FUNCTION public.block_update();


--
-- Name: order_type trg_block_update_order_type; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_update_order_type BEFORE UPDATE ON public.order_type FOR EACH ROW EXECUTE FUNCTION public.block_update();


--
-- Name: transaction_types trg_block_update_transaction_types; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_update_transaction_types BEFORE UPDATE ON public.transaction_types FOR EACH ROW EXECUTE FUNCTION public.block_update();


--
-- Name: transactions trg_block_update_transactions; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_block_update_transactions BEFORE UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public.block_update();


--
-- Name: balance_history balance_history_savings_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.balance_history
    ADD CONSTRAINT balance_history_savings_account_id_fkey FOREIGN KEY (savings_account_id) REFERENCES public.savings_accounts(id);


--
-- Name: balance_history balance_history_transaction_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.balance_history
    ADD CONSTRAINT balance_history_transaction_type_fkey FOREIGN KEY (transaction_type) REFERENCES public.transaction_types(id);


--
-- Name: bonds bonds_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds
    ADD CONSTRAINT bonds_id_fkey FOREIGN KEY (id) REFERENCES public.securities(id);


--
-- Name: bonds_payments bonds_payments_bond_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds_payments
    ADD CONSTRAINT bonds_payments_bond_id_fkey FOREIGN KEY (bond_id) REFERENCES public.bonds(id);


--
-- Name: bonds_payments bonds_payments_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds_payments
    ADD CONSTRAINT bonds_payments_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES public.currencies(id);


--
-- Name: bonds_payments bonds_payments_payment_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bonds_payments
    ADD CONSTRAINT bonds_payments_payment_type_fkey FOREIGN KEY (payment_type) REFERENCES public.bond_payment_types(id);


--
-- Name: customer_portfolios current_portfolio_customer_account_id__fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_portfolios
    ADD CONSTRAINT current_portfolio_customer_account_id__fk FOREIGN KEY (customer_account_id) REFERENCES public.customer_accounts(id);


--
-- Name: customer_portfolios current_portfolio_security_id__fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_portfolios
    ADD CONSTRAINT current_portfolio_security_id__fk FOREIGN KEY (security_id) REFERENCES public.securities(id);


--
-- Name: customer_accounts customer_accounts_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customer_accounts
    ADD CONSTRAINT customer_accounts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: orders fk_orders_customer_account; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_customer_account FOREIGN KEY (customer_account_id) REFERENCES public.customer_accounts(id);


--
-- Name: orders fk_orders_order_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_order_status FOREIGN KEY (order_status_id) REFERENCES public.order_status(id);


--
-- Name: orders fk_orders_order_type; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_order_type FOREIGN KEY (order_type_id) REFERENCES public.order_type(id);


--
-- Name: orders fk_orders_savings_account; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_savings_account FOREIGN KEY (savings_account_id) REFERENCES public.savings_accounts(id);


--
-- Name: orders fk_orders_security; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_security FOREIGN KEY (security_id) REFERENCES public.securities(id);


--
-- Name: transactions fk_transactions_buy_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_buy_order FOREIGN KEY (buy_order_id) REFERENCES public.orders(id);


--
-- Name: transactions fk_transactions_sell_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transactions
    ADD CONSTRAINT fk_transactions_sell_order FOREIGN KEY (sell_order_id) REFERENCES public.orders(id);


--
-- Name: savings_accounts savings_accounts_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts
    ADD CONSTRAINT savings_accounts_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES public.currencies(id);


--
-- Name: savings_accounts savings_accounts_customer_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.savings_accounts
    ADD CONSTRAINT savings_accounts_customer_account_id_fkey FOREIGN KEY (customer_account_id) REFERENCES public.customer_accounts(id);


--
-- Name: securities securities_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities
    ADD CONSTRAINT securities_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES public.currencies(id);


--
-- Name: securities securities_security_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities
    ADD CONSTRAINT securities_security_type_fkey FOREIGN KEY (security_type) REFERENCES public.security_types(id);


--
-- Name: securities securities_stock_exchange_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.securities
    ADD CONSTRAINT securities_stock_exchange_fkey FOREIGN KEY (stock_exchange) REFERENCES public.stock_exchanges(id);


--
-- Name: stocks stocks_dividend_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_dividend_currency_id_fkey FOREIGN KEY (dividend_currency_id) REFERENCES public.currencies(id);


--
-- Name: stocks stocks_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_id_fkey FOREIGN KEY (id) REFERENCES public.securities(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO app_developer;


--
-- Name: FUNCTION cancel_order(p_order_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.cancel_order(p_order_id integer) TO app_developer;


--
-- Name: PROCEDURE create_buy_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.create_buy_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer) TO app_developer;


--
-- Name: PROCEDURE create_sell_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.create_sell_order(IN p_security_id integer, IN p_price numeric, IN p_quantity integer, IN p_savings_account_id integer) TO app_developer;


--
-- Name: PROCEDURE deposit_balance(IN p_amount numeric, IN p_savings_account_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.deposit_balance(IN p_amount numeric, IN p_savings_account_id integer) TO app_developer;


--
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.orders TO app_developer;


--
-- Name: PROCEDURE withdraw_balance(IN p_amount numeric, IN p_savings_account_id integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON PROCEDURE public.withdraw_balance(IN p_amount numeric, IN p_savings_account_id integer) TO app_developer;


--
-- Name: TABLE balance_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.balance_history TO app_developer;


--
-- Name: TABLE bond_payment_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.bond_payment_types TO app_developer;


--
-- Name: TABLE bonds; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.bonds TO app_developer;


--
-- Name: TABLE bonds_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.bonds_payments TO app_developer;


--
-- Name: TABLE currencies; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.currencies TO app_developer;


--
-- Name: TABLE customer_accounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.customer_accounts TO app_developer;


--
-- Name: COLUMN customer_accounts.phone_number; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(phone_number) ON TABLE public.customer_accounts TO app_developer;


--
-- Name: COLUMN customer_accounts.email; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(email) ON TABLE public.customer_accounts TO app_developer;


--
-- Name: SEQUENCE customer_accounts_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.customer_accounts_id_seq TO app_developer;


--
-- Name: TABLE customer_portfolios; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.customer_portfolios TO app_developer;


--
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.customers TO app_developer;


--
-- Name: COLUMN customers.first_name; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(first_name) ON TABLE public.customers TO app_developer;


--
-- Name: COLUMN customers.last_name; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(last_name) ON TABLE public.customers TO app_developer;


--
-- Name: COLUMN customers.address; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(address) ON TABLE public.customers TO app_developer;


--
-- Name: SEQUENCE customers_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.customers_id_seq TO app_developer;


--
-- Name: TABLE order_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.order_status TO app_developer;


--
-- Name: TABLE order_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.order_type TO app_developer;


--
-- Name: TABLE realized_profit_by_security_view; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.realized_profit_by_security_view TO app_developer;


--
-- Name: TABLE savings_accounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.savings_accounts TO app_developer;


--
-- Name: SEQUENCE savings_accounts_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.savings_accounts_id_seq TO app_developer;


--
-- Name: TABLE securities; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,UPDATE ON TABLE public.securities TO app_developer;


--
-- Name: COLUMN securities.last_price; Type: ACL; Schema: public; Owner: postgres
--

GRANT UPDATE(last_price) ON TABLE public.securities TO app_developer;


--
-- Name: TABLE security_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.security_types TO app_developer;


--
-- Name: TABLE stock_exchanges; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.stock_exchanges TO app_developer;


--
-- Name: TABLE stocks; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.stocks TO app_developer;


--
-- Name: TABLE unrealized_profit_by_security_view; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.unrealized_profit_by_security_view TO app_developer;


--
-- Name: TABLE total_profit_by_security; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.total_profit_by_security TO app_developer;


--
-- Name: TABLE total_profit_by_portfolio; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.total_profit_by_portfolio TO app_developer;


--
-- Name: TABLE total_realized_profit; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.total_realized_profit TO app_developer;


--
-- Name: TABLE total_unrealized_profit; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.total_unrealized_profit TO app_developer;


--
-- Name: TABLE transaction_types; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.transaction_types TO app_developer;


--
-- Name: TABLE transactions; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.transactions TO app_developer;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT SELECT ON TABLES TO app_developer;


--
-- PostgreSQL database dump complete
--

